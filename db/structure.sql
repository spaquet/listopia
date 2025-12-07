SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET transaction_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: hstore; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS hstore WITH SCHEMA public;


--
-- Name: EXTENSION hstore; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION hstore IS 'data type for storing sets of (key, value) pairs';


--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: logidze_capture_exception(jsonb); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.logidze_capture_exception(error_data jsonb) RETURNS boolean
    LANGUAGE plpgsql
    AS $$
  -- version: 1
BEGIN
  -- Feel free to change this function to change Logidze behavior on exception.
  --
  -- Return `false` to raise exception or `true` to commit record changes.
  --
  -- `error_data` contains:
  --   - returned_sqlstate
  --   - message_text
  --   - pg_exception_detail
  --   - pg_exception_hint
  --   - pg_exception_context
  --   - schema_name
  --   - table_name
  -- Learn more about available keys:
  -- https://www.postgresql.org/docs/9.6/plpgsql-control-structures.html#PLPGSQL-EXCEPTION-DIAGNOSTICS-VALUES
  --

  return false;
END;
$$;


--
-- Name: logidze_compact_history(jsonb, integer); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.logidze_compact_history(log_data jsonb, cutoff integer DEFAULT 1) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
  -- version: 1
  DECLARE
    merged jsonb;
  BEGIN
    LOOP
      merged := jsonb_build_object(
        'ts',
        log_data#>'{h,1,ts}',
        'v',
        log_data#>'{h,1,v}',
        'c',
        (log_data#>'{h,0,c}') || (log_data#>'{h,1,c}')
      );

      IF (log_data#>'{h,1}' ? 'm') THEN
        merged := jsonb_set(merged, ARRAY['m'], log_data#>'{h,1,m}');
      END IF;

      log_data := jsonb_set(
        log_data,
        '{h}',
        jsonb_set(
          log_data->'h',
          '{1}',
          merged
        ) - 0
      );

      cutoff := cutoff - 1;

      EXIT WHEN cutoff <= 0;
    END LOOP;

    return log_data;
  END;
$$;


--
-- Name: logidze_filter_keys(jsonb, text[], boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.logidze_filter_keys(obj jsonb, keys text[], include_columns boolean DEFAULT false) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
  -- version: 1
  DECLARE
    res jsonb;
    key text;
  BEGIN
    res := '{}';

    IF include_columns THEN
      FOREACH key IN ARRAY keys
      LOOP
        IF obj ? key THEN
          res = jsonb_insert(res, ARRAY[key], obj->key);
        END IF;
      END LOOP;
    ELSE
      res = obj;
      FOREACH key IN ARRAY keys
      LOOP
        res = res - key;
      END LOOP;
    END IF;

    RETURN res;
  END;
$$;


--
-- Name: logidze_logger(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.logidze_logger() RETURNS trigger
    LANGUAGE plpgsql
    AS $_$
  -- version: 5
  DECLARE
    changes jsonb;
    version jsonb;
    full_snapshot boolean;
    log_data jsonb;
    new_v integer;
    size integer;
    history_limit integer;
    debounce_time integer;
    current_version integer;
    k text;
    iterator integer;
    item record;
    columns text[];
    include_columns boolean;
    detached_log_data jsonb;
    -- We use `detached_loggable_type` for:
    -- 1. Checking if current implementation is `--detached` (`log_data` is stored in a separated table)
    -- 2. If implementation is `--detached` then we use detached_loggable_type to determine
    --    to which table current `log_data` record belongs
    detached_loggable_type text;
    log_data_table_name text;
    log_data_is_empty boolean;
    log_data_ts_key_data text;
    ts timestamp with time zone;
    ts_column text;
    err_sqlstate text;
    err_message text;
    err_detail text;
    err_hint text;
    err_context text;
    err_table_name text;
    err_schema_name text;
    err_jsonb jsonb;
    err_captured boolean;
  BEGIN
    ts_column := NULLIF(TG_ARGV[1], 'null');
    columns := NULLIF(TG_ARGV[2], 'null');
    include_columns := NULLIF(TG_ARGV[3], 'null');
    detached_loggable_type := NULLIF(TG_ARGV[5], 'null');
    log_data_table_name := NULLIF(TG_ARGV[6], 'null');

    -- getting previous log_data if it exists for detached `log_data` storage variant
    IF detached_loggable_type IS NOT NULL
    THEN
      EXECUTE format(
        'SELECT ldtn.log_data ' ||
        'FROM %I ldtn ' ||
        'WHERE ldtn.loggable_type = $1 ' ||
          'AND ldtn.loggable_id = $2 '  ||
        'LIMIT 1',
        log_data_table_name
      ) USING detached_loggable_type, NEW.id INTO detached_log_data;
    END IF;

    IF detached_loggable_type IS NULL
    THEN
        log_data_is_empty = NEW.log_data is NULL OR NEW.log_data = '{}'::jsonb;
    ELSE
        log_data_is_empty = detached_log_data IS NULL OR detached_log_data = '{}'::jsonb;
    END IF;

    IF log_data_is_empty
    THEN
      IF columns IS NOT NULL THEN
        log_data = logidze_snapshot(to_jsonb(NEW.*), ts_column, columns, include_columns);
      ELSE
        log_data = logidze_snapshot(to_jsonb(NEW.*), ts_column);
      END IF;

      IF log_data#>>'{h, -1, c}' != '{}' THEN
        IF detached_loggable_type IS NULL
        THEN
          NEW.log_data := log_data;
        ELSE
          EXECUTE format(
            'INSERT INTO %I(log_data, loggable_type, loggable_id) ' ||
            'VALUES ($1, $2, $3);',
            log_data_table_name
          ) USING log_data, detached_loggable_type, NEW.id;
        END IF;
      END IF;

    ELSE

      IF TG_OP = 'UPDATE' AND (to_jsonb(NEW.*) = to_jsonb(OLD.*)) THEN
        RETURN NEW; -- pass
      END IF;

      history_limit := NULLIF(TG_ARGV[0], 'null');
      debounce_time := NULLIF(TG_ARGV[4], 'null');

      IF detached_loggable_type IS NULL
      THEN
          log_data := NEW.log_data;
      ELSE
          log_data := detached_log_data;
      END IF;

      current_version := (log_data->>'v')::int;

      IF ts_column IS NULL THEN
        ts := statement_timestamp();
      ELSEIF TG_OP = 'UPDATE' THEN
        ts := (to_jsonb(NEW.*) ->> ts_column)::timestamp with time zone;
        IF ts IS NULL OR ts = (to_jsonb(OLD.*) ->> ts_column)::timestamp with time zone THEN
          ts := statement_timestamp();
        END IF;
      ELSEIF TG_OP = 'INSERT' THEN
        ts := (to_jsonb(NEW.*) ->> ts_column)::timestamp with time zone;

        IF detached_loggable_type IS NULL
        THEN
          log_data_ts_key_data = NEW.log_data #>> '{h,-1,ts}';
        ELSE
          log_data_ts_key_data = detached_log_data #>> '{h,-1,ts}';
        END IF;

        IF ts IS NULL OR (extract(epoch from ts) * 1000)::bigint = log_data_ts_key_data::bigint THEN
            ts := statement_timestamp();
        END IF;
      END IF;

      full_snapshot := (coalesce(current_setting('logidze.full_snapshot', true), '') = 'on') OR (TG_OP = 'INSERT');

      IF current_version < (log_data#>>'{h,-1,v}')::int THEN
        iterator := 0;
        FOR item in SELECT * FROM jsonb_array_elements(log_data->'h')
        LOOP
          IF (item.value->>'v')::int > current_version THEN
            log_data := jsonb_set(
              log_data,
              '{h}',
              (log_data->'h') - iterator
            );
          END IF;
          iterator := iterator + 1;
        END LOOP;
      END IF;

      changes := '{}';

      IF full_snapshot THEN
        BEGIN
          changes = hstore_to_jsonb_loose(hstore(NEW.*));
        EXCEPTION
          WHEN NUMERIC_VALUE_OUT_OF_RANGE THEN
            changes = row_to_json(NEW.*)::jsonb;
            FOR k IN (SELECT key FROM jsonb_each(changes))
            LOOP
              IF jsonb_typeof(changes->k) = 'object' THEN
                changes = jsonb_set(changes, ARRAY[k], to_jsonb(changes->>k));
              END IF;
            END LOOP;
        END;
      ELSE
        BEGIN
          changes = hstore_to_jsonb_loose(
                hstore(NEW.*) - hstore(OLD.*)
            );
        EXCEPTION
          WHEN NUMERIC_VALUE_OUT_OF_RANGE THEN
            changes = (SELECT
              COALESCE(json_object_agg(key, value), '{}')::jsonb
              FROM
              jsonb_each(row_to_json(NEW.*)::jsonb)
              WHERE NOT jsonb_build_object(key, value) <@ row_to_json(OLD.*)::jsonb);
            FOR k IN (SELECT key FROM jsonb_each(changes))
            LOOP
              IF jsonb_typeof(changes->k) = 'object' THEN
                changes = jsonb_set(changes, ARRAY[k], to_jsonb(changes->>k));
              END IF;
            END LOOP;
        END;
      END IF;

      -- We store `log_data` in a separate table for the `detached` mode
      -- So we remove `log_data` only when we store historic data in the record's origin table
      IF detached_loggable_type IS NULL
      THEN
          changes = changes - 'log_data';
      END IF;

      IF columns IS NOT NULL THEN
        changes = logidze_filter_keys(changes, columns, include_columns);
      END IF;

      IF changes = '{}' THEN
        RETURN NEW; -- pass
      END IF;

      new_v := (log_data#>>'{h,-1,v}')::int + 1;

      size := jsonb_array_length(log_data->'h');
      version := logidze_version(new_v, changes, ts);

      IF (
        debounce_time IS NOT NULL AND
        (version->>'ts')::bigint - (log_data#>'{h,-1,ts}')::text::bigint <= debounce_time
      ) THEN
        -- merge new version with the previous one
        new_v := (log_data#>>'{h,-1,v}')::int;
        version := logidze_version(new_v, (log_data#>'{h,-1,c}')::jsonb || changes, ts);
        -- remove the previous version from log
        log_data := jsonb_set(
          log_data,
          '{h}',
          (log_data->'h') - (size - 1)
        );
      END IF;

      log_data := jsonb_set(
        log_data,
        ARRAY['h', size::text],
        version,
        true
      );

      log_data := jsonb_set(
        log_data,
        '{v}',
        to_jsonb(new_v)
      );

      IF history_limit IS NOT NULL AND history_limit <= size THEN
        log_data := logidze_compact_history(log_data, size - history_limit + 1);
      END IF;

      IF detached_loggable_type IS NULL
      THEN
        NEW.log_data := log_data;
      ELSE
        detached_log_data = log_data;
        EXECUTE format(
          'UPDATE %I ' ||
          'SET log_data = $1 ' ||
          'WHERE %I.loggable_type = $2 ' ||
          'AND %I.loggable_id = $3',
          log_data_table_name,
          log_data_table_name,
          log_data_table_name
        ) USING detached_log_data, detached_loggable_type, NEW.id;
      END IF;
    END IF;

    RETURN NEW; -- result
  EXCEPTION
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS err_sqlstate = RETURNED_SQLSTATE,
                              err_message = MESSAGE_TEXT,
                              err_detail = PG_EXCEPTION_DETAIL,
                              err_hint = PG_EXCEPTION_HINT,
                              err_context = PG_EXCEPTION_CONTEXT,
                              err_schema_name = SCHEMA_NAME,
                              err_table_name = TABLE_NAME;
      err_jsonb := jsonb_build_object(
        'returned_sqlstate', err_sqlstate,
        'message_text', err_message,
        'pg_exception_detail', err_detail,
        'pg_exception_hint', err_hint,
        'pg_exception_context', err_context,
        'schema_name', err_schema_name,
        'table_name', err_table_name
      );
      err_captured = logidze_capture_exception(err_jsonb);
      IF err_captured THEN
        return NEW;
      ELSE
        RAISE;
      END IF;
  END;
$_$;


--
-- Name: logidze_logger_after(); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.logidze_logger_after() RETURNS trigger
    LANGUAGE plpgsql
    AS $_$
  -- version: 5


  DECLARE
    changes jsonb;
    version jsonb;
    full_snapshot boolean;
    log_data jsonb;
    new_v integer;
    size integer;
    history_limit integer;
    debounce_time integer;
    current_version integer;
    k text;
    iterator integer;
    item record;
    columns text[];
    include_columns boolean;
    detached_log_data jsonb;
    -- We use `detached_loggable_type` for:
    -- 1. Checking if current implementation is `--detached` (`log_data` is stored in a separated table)
    -- 2. If implementation is `--detached` then we use detached_loggable_type to determine
    --    to which table current `log_data` record belongs
    detached_loggable_type text;
    log_data_table_name text;
    log_data_is_empty boolean;
    log_data_ts_key_data text;
    ts timestamp with time zone;
    ts_column text;
    err_sqlstate text;
    err_message text;
    err_detail text;
    err_hint text;
    err_context text;
    err_table_name text;
    err_schema_name text;
    err_jsonb jsonb;
    err_captured boolean;
  BEGIN
    ts_column := NULLIF(TG_ARGV[1], 'null');
    columns := NULLIF(TG_ARGV[2], 'null');
    include_columns := NULLIF(TG_ARGV[3], 'null');
    detached_loggable_type := NULLIF(TG_ARGV[5], 'null');
    log_data_table_name := NULLIF(TG_ARGV[6], 'null');

    -- getting previous log_data if it exists for detached `log_data` storage variant
    IF detached_loggable_type IS NOT NULL
    THEN
      EXECUTE format(
        'SELECT ldtn.log_data ' ||
        'FROM %I ldtn ' ||
        'WHERE ldtn.loggable_type = $1 ' ||
          'AND ldtn.loggable_id = $2 '  ||
        'LIMIT 1',
        log_data_table_name
      ) USING detached_loggable_type, NEW.id INTO detached_log_data;
    END IF;

    IF detached_loggable_type IS NULL
    THEN
        log_data_is_empty = NEW.log_data is NULL OR NEW.log_data = '{}'::jsonb;
    ELSE
        log_data_is_empty = detached_log_data IS NULL OR detached_log_data = '{}'::jsonb;
    END IF;

    IF log_data_is_empty
    THEN
      IF columns IS NOT NULL THEN
        log_data = logidze_snapshot(to_jsonb(NEW.*), ts_column, columns, include_columns);
      ELSE
        log_data = logidze_snapshot(to_jsonb(NEW.*), ts_column);
      END IF;

      IF log_data#>>'{h, -1, c}' != '{}' THEN
        IF detached_loggable_type IS NULL
        THEN
          NEW.log_data := log_data;
        ELSE
          EXECUTE format(
            'INSERT INTO %I(log_data, loggable_type, loggable_id) ' ||
            'VALUES ($1, $2, $3);',
            log_data_table_name
          ) USING log_data, detached_loggable_type, NEW.id;
        END IF;
      END IF;

    ELSE

      IF TG_OP = 'UPDATE' AND (to_jsonb(NEW.*) = to_jsonb(OLD.*)) THEN
        RETURN NULL;
      END IF;

      history_limit := NULLIF(TG_ARGV[0], 'null');
      debounce_time := NULLIF(TG_ARGV[4], 'null');

      IF detached_loggable_type IS NULL
      THEN
          log_data := NEW.log_data;
      ELSE
          log_data := detached_log_data;
      END IF;

      current_version := (log_data->>'v')::int;

      IF ts_column IS NULL THEN
        ts := statement_timestamp();
      ELSEIF TG_OP = 'UPDATE' THEN
        ts := (to_jsonb(NEW.*) ->> ts_column)::timestamp with time zone;
        IF ts IS NULL OR ts = (to_jsonb(OLD.*) ->> ts_column)::timestamp with time zone THEN
          ts := statement_timestamp();
        END IF;
      ELSEIF TG_OP = 'INSERT' THEN
        ts := (to_jsonb(NEW.*) ->> ts_column)::timestamp with time zone;

        IF detached_loggable_type IS NULL
        THEN
          log_data_ts_key_data = NEW.log_data #>> '{h,-1,ts}';
        ELSE
          log_data_ts_key_data = detached_log_data #>> '{h,-1,ts}';
        END IF;

        IF ts IS NULL OR (extract(epoch from ts) * 1000)::bigint = log_data_ts_key_data::bigint THEN
            ts := statement_timestamp();
        END IF;
      END IF;

      full_snapshot := (coalesce(current_setting('logidze.full_snapshot', true), '') = 'on') OR (TG_OP = 'INSERT');

      IF current_version < (log_data#>>'{h,-1,v}')::int THEN
        iterator := 0;
        FOR item in SELECT * FROM jsonb_array_elements(log_data->'h')
        LOOP
          IF (item.value->>'v')::int > current_version THEN
            log_data := jsonb_set(
              log_data,
              '{h}',
              (log_data->'h') - iterator
            );
          END IF;
          iterator := iterator + 1;
        END LOOP;
      END IF;

      changes := '{}';

      IF full_snapshot THEN
        BEGIN
          changes = hstore_to_jsonb_loose(hstore(NEW.*));
        EXCEPTION
          WHEN NUMERIC_VALUE_OUT_OF_RANGE THEN
            changes = row_to_json(NEW.*)::jsonb;
            FOR k IN (SELECT key FROM jsonb_each(changes))
            LOOP
              IF jsonb_typeof(changes->k) = 'object' THEN
                changes = jsonb_set(changes, ARRAY[k], to_jsonb(changes->>k));
              END IF;
            END LOOP;
        END;
      ELSE
        BEGIN
          changes = hstore_to_jsonb_loose(
                hstore(NEW.*) - hstore(OLD.*)
            );
        EXCEPTION
          WHEN NUMERIC_VALUE_OUT_OF_RANGE THEN
            changes = (SELECT
              COALESCE(json_object_agg(key, value), '{}')::jsonb
              FROM
              jsonb_each(row_to_json(NEW.*)::jsonb)
              WHERE NOT jsonb_build_object(key, value) <@ row_to_json(OLD.*)::jsonb);
            FOR k IN (SELECT key FROM jsonb_each(changes))
            LOOP
              IF jsonb_typeof(changes->k) = 'object' THEN
                changes = jsonb_set(changes, ARRAY[k], to_jsonb(changes->>k));
              END IF;
            END LOOP;
        END;
      END IF;

      -- We store `log_data` in a separate table for the `detached` mode
      -- So we remove `log_data` only when we store historic data in the record's origin table
      IF detached_loggable_type IS NULL
      THEN
          changes = changes - 'log_data';
      END IF;

      IF columns IS NOT NULL THEN
        changes = logidze_filter_keys(changes, columns, include_columns);
      END IF;

      IF changes = '{}' THEN
        RETURN NULL;
      END IF;

      new_v := (log_data#>>'{h,-1,v}')::int + 1;

      size := jsonb_array_length(log_data->'h');
      version := logidze_version(new_v, changes, ts);

      IF (
        debounce_time IS NOT NULL AND
        (version->>'ts')::bigint - (log_data#>'{h,-1,ts}')::text::bigint <= debounce_time
      ) THEN
        -- merge new version with the previous one
        new_v := (log_data#>>'{h,-1,v}')::int;
        version := logidze_version(new_v, (log_data#>'{h,-1,c}')::jsonb || changes, ts);
        -- remove the previous version from log
        log_data := jsonb_set(
          log_data,
          '{h}',
          (log_data->'h') - (size - 1)
        );
      END IF;

      log_data := jsonb_set(
        log_data,
        ARRAY['h', size::text],
        version,
        true
      );

      log_data := jsonb_set(
        log_data,
        '{v}',
        to_jsonb(new_v)
      );

      IF history_limit IS NOT NULL AND history_limit <= size THEN
        log_data := logidze_compact_history(log_data, size - history_limit + 1);
      END IF;

      IF detached_loggable_type IS NULL
      THEN
        NEW.log_data := log_data;
      ELSE
        detached_log_data = log_data;
        EXECUTE format(
          'UPDATE %I ' ||
          'SET log_data = $1 ' ||
          'WHERE %I.loggable_type = $2 ' ||
          'AND %I.loggable_id = $3',
          log_data_table_name,
          log_data_table_name,
          log_data_table_name
        ) USING detached_log_data, detached_loggable_type, NEW.id;
      END IF;
    END IF;

    IF detached_loggable_type IS NULL
    THEN
      EXECUTE format('UPDATE %I.%I SET "log_data" = $1 WHERE ctid = %L', TG_TABLE_SCHEMA, TG_TABLE_NAME, NEW.CTID) USING NEW.log_data;
    END IF;

    RETURN NULL;

  EXCEPTION
    WHEN OTHERS THEN
      GET STACKED DIAGNOSTICS err_sqlstate = RETURNED_SQLSTATE,
                              err_message = MESSAGE_TEXT,
                              err_detail = PG_EXCEPTION_DETAIL,
                              err_hint = PG_EXCEPTION_HINT,
                              err_context = PG_EXCEPTION_CONTEXT,
                              err_schema_name = SCHEMA_NAME,
                              err_table_name = TABLE_NAME;
      err_jsonb := jsonb_build_object(
        'returned_sqlstate', err_sqlstate,
        'message_text', err_message,
        'pg_exception_detail', err_detail,
        'pg_exception_hint', err_hint,
        'pg_exception_context', err_context,
        'schema_name', err_schema_name,
        'table_name', err_table_name
      );
      err_captured = logidze_capture_exception(err_jsonb);
      IF err_captured THEN
        return NEW;
      ELSE
        RAISE;
      END IF;
  END;
$_$;


--
-- Name: logidze_snapshot(jsonb, text, text[], boolean); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.logidze_snapshot(item jsonb, ts_column text DEFAULT NULL::text, columns text[] DEFAULT NULL::text[], include_columns boolean DEFAULT false) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
  -- version: 3
  DECLARE
    ts timestamp with time zone;
    k text;
  BEGIN
    item = item - 'log_data';
    IF ts_column IS NULL THEN
      ts := statement_timestamp();
    ELSE
      ts := coalesce((item->>ts_column)::timestamp with time zone, statement_timestamp());
    END IF;

    IF columns IS NOT NULL THEN
      item := logidze_filter_keys(item, columns, include_columns);
    END IF;

    FOR k IN (SELECT key FROM jsonb_each(item))
    LOOP
      IF jsonb_typeof(item->k) = 'object' THEN
         item := jsonb_set(item, ARRAY[k], to_jsonb(item->>k));
      END IF;
    END LOOP;

    return json_build_object(
      'v', 1,
      'h', jsonb_build_array(
              logidze_version(1, item, ts)
            )
      );
  END;
$$;


--
-- Name: logidze_version(bigint, jsonb, timestamp with time zone); Type: FUNCTION; Schema: public; Owner: -
--

CREATE FUNCTION public.logidze_version(v bigint, data jsonb, ts timestamp with time zone) RETURNS jsonb
    LANGUAGE plpgsql
    AS $$
  -- version: 2
  DECLARE
    buf jsonb;
  BEGIN
    data = data - 'log_data';
    buf := jsonb_build_object(
              'ts',
              (extract(epoch from ts) * 1000)::bigint,
              'v',
              v,
              'c',
              data
              );
    IF coalesce(current_setting('logidze.meta', true), '') <> '' THEN
      buf := jsonb_insert(buf, '{m}', current_setting('logidze.meta')::jsonb);
    END IF;
    RETURN buf;
  END;
$$;


SET default_tablespace = '';

SET default_table_access_method = heap;

--
-- Name: active_storage_attachments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_attachments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying NOT NULL,
    record_type character varying NOT NULL,
    record_id uuid NOT NULL,
    blob_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: active_storage_blobs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_blobs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    key character varying NOT NULL,
    filename character varying NOT NULL,
    content_type character varying,
    metadata text,
    service_name character varying NOT NULL,
    byte_size bigint NOT NULL,
    checksum character varying,
    created_at timestamp(6) without time zone NOT NULL
);


--
-- Name: active_storage_variant_records; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.active_storage_variant_records (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    blob_id uuid NOT NULL,
    variation_digest character varying NOT NULL
);


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: board_columns; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.board_columns (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    list_id uuid NOT NULL,
    name character varying NOT NULL,
    "position" integer DEFAULT 0 NOT NULL,
    metadata json DEFAULT '{}'::json,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: chats; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.chats (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    title character varying(255),
    context json DEFAULT '{}'::json,
    status character varying DEFAULT 'active'::character varying,
    last_message_at timestamp(6) without time zone,
    metadata json DEFAULT '{}'::json,
    model_id_string character varying,
    last_stable_at timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    conversation_state character varying DEFAULT 'stable'::character varying,
    last_cleanup_at timestamp(6) without time zone,
    model_id bigint
);


--
-- Name: collaborators; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.collaborators (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    collaboratable_type character varying NOT NULL,
    collaboratable_id uuid NOT NULL,
    user_id uuid NOT NULL,
    organization_id uuid,
    permission integer DEFAULT 0 NOT NULL,
    granted_roles character varying[] DEFAULT '{}'::character varying[] NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: comments; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.comments (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    commentable_type character varying NOT NULL,
    commentable_id uuid NOT NULL,
    user_id uuid NOT NULL,
    content text NOT NULL,
    metadata json DEFAULT '{}'::json,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: currents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.currents (
    id bigint NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: currents_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.currents_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: currents_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.currents_id_seq OWNED BY public.currents.id;


--
-- Name: invitations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.invitations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    invitable_type character varying NOT NULL,
    invitable_id uuid NOT NULL,
    user_id uuid,
    organization_id uuid,
    email character varying,
    invitation_token character varying,
    invitation_sent_at timestamp(6) without time zone,
    invitation_accepted_at timestamp(6) without time zone,
    invitation_expires_at timestamp(6) without time zone,
    invited_by_id uuid,
    permission integer DEFAULT 0 NOT NULL,
    granted_roles character varying[] DEFAULT '{}'::character varying[] NOT NULL,
    message text,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: list_items; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.list_items (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    list_id uuid NOT NULL,
    assigned_user_id uuid,
    title character varying NOT NULL,
    description text,
    item_type integer DEFAULT 0 NOT NULL,
    priority integer DEFAULT 1 NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    status_changed_at timestamp(6) without time zone,
    due_date timestamp(6) without time zone,
    reminder_at timestamp(6) without time zone,
    skip_notifications boolean DEFAULT false NOT NULL,
    "position" integer DEFAULT 0,
    estimated_duration numeric(10,2) DEFAULT 0.0 NOT NULL,
    total_tracked_time numeric(10,2) DEFAULT 0.0 NOT NULL,
    start_date timestamp(6) without time zone,
    duration_days integer,
    url character varying,
    metadata json DEFAULT '{}'::json,
    recurrence_rule character varying DEFAULT 'none'::character varying NOT NULL,
    recurrence_end_date timestamp(6) without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    board_column_id uuid,
    completed_at timestamp(6) without time zone
);


--
-- Name: lists; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.lists (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    title character varying NOT NULL,
    description text,
    status integer DEFAULT 0 NOT NULL,
    is_public boolean DEFAULT false NOT NULL,
    public_permission integer DEFAULT 0 NOT NULL,
    public_slug character varying,
    list_type integer DEFAULT 0 NOT NULL,
    parent_list_id uuid,
    organization_id uuid,
    team_id uuid,
    metadata json DEFAULT '{}'::json,
    color_theme character varying DEFAULT 'blue'::character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    list_items_count integer DEFAULT 0 NOT NULL,
    list_collaborations_count integer DEFAULT 0 NOT NULL
);


--
-- Name: logidze_data; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.logidze_data (
    id bigint NOT NULL,
    log_data jsonb,
    loggable_type character varying,
    loggable_id bigint
);


--
-- Name: logidze_data_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.logidze_data_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: logidze_data_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.logidze_data_id_seq OWNED BY public.logidze_data.id;


--
-- Name: messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.messages (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    chat_id uuid NOT NULL,
    user_id uuid,
    model_id bigint,
    role character varying NOT NULL,
    content text,
    tool_calls json DEFAULT '[]'::json,
    tool_call_results json DEFAULT '[]'::json,
    context_snapshot json DEFAULT '{}'::json,
    message_type character varying DEFAULT 'text'::character varying,
    metadata json DEFAULT '{}'::json,
    llm_provider character varying,
    llm_model character varying,
    model_id_string character varying,
    tool_call_id character varying,
    token_count integer,
    input_tokens integer,
    output_tokens integer,
    processing_time numeric(8,3),
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    cached_tokens integer,
    cache_creation_tokens integer,
    content_raw json,
    CONSTRAINT tool_messages_must_have_tool_call_id CHECK ((((role)::text <> 'tool'::text) OR (tool_call_id IS NOT NULL)))
);


--
-- Name: models; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.models (
    id bigint NOT NULL,
    model_id character varying NOT NULL,
    name character varying NOT NULL,
    provider character varying NOT NULL,
    family character varying,
    model_created_at timestamp(6) without time zone,
    context_window integer,
    max_output_tokens integer,
    knowledge_cutoff date,
    modalities jsonb DEFAULT '{}'::jsonb,
    capabilities jsonb DEFAULT '[]'::jsonb,
    pricing jsonb DEFAULT '{}'::jsonb,
    metadata jsonb DEFAULT '{}'::jsonb,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: models_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.models_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: models_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.models_id_seq OWNED BY public.models.id;


--
-- Name: noticed_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.noticed_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    type character varying,
    record_type character varying,
    record_id uuid,
    params jsonb,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    notifications_count integer
);


--
-- Name: noticed_notifications; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.noticed_notifications (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    type character varying,
    event_id uuid NOT NULL,
    recipient_type character varying NOT NULL,
    recipient_id uuid NOT NULL,
    read_at timestamp without time zone,
    seen_at timestamp without time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: notification_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.notification_settings (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    email_notifications boolean DEFAULT true NOT NULL,
    sms_notifications boolean DEFAULT false NOT NULL,
    push_notifications boolean DEFAULT true NOT NULL,
    collaboration_notifications boolean DEFAULT true NOT NULL,
    list_activity_notifications boolean DEFAULT true NOT NULL,
    item_activity_notifications boolean DEFAULT true NOT NULL,
    status_change_notifications boolean DEFAULT true NOT NULL,
    notification_frequency character varying DEFAULT 'immediate'::character varying NOT NULL,
    quiet_hours_start time without time zone,
    quiet_hours_end time without time zone,
    timezone character varying DEFAULT 'UTC'::character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: organization_memberships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organization_memberships (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    user_id uuid NOT NULL,
    role integer DEFAULT 0 NOT NULL,
    status integer DEFAULT 1 NOT NULL,
    joined_at timestamp(6) without time zone NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: organizations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.organizations (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying NOT NULL,
    slug character varying NOT NULL,
    size integer DEFAULT 0 NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    created_by_id uuid NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: recovery_contexts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.recovery_contexts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    chat_id uuid NOT NULL,
    context_data text,
    expires_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: relationships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.relationships (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    parent_type character varying NOT NULL,
    parent_id uuid NOT NULL,
    child_type character varying NOT NULL,
    child_id uuid NOT NULL,
    relationship_type integer DEFAULT 0 NOT NULL,
    metadata json DEFAULT '{}'::json,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.roles (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying,
    resource_type character varying,
    resource_id uuid,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: sessions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.sessions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    session_token character varying NOT NULL,
    ip_address character varying,
    user_agent character varying,
    last_accessed_at timestamp(6) without time zone DEFAULT CURRENT_TIMESTAMP,
    expires_at timestamp(6) without time zone NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: taggings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.taggings (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    tag_id uuid,
    taggable_type character varying,
    taggable_id uuid,
    tagger_type character varying,
    tagger_id uuid,
    context character varying(128),
    created_at timestamp without time zone,
    tenant character varying(128)
);


--
-- Name: tags; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tags (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    taggings_count integer DEFAULT 0
);


--
-- Name: team_memberships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.team_memberships (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    team_id uuid NOT NULL,
    user_id uuid NOT NULL,
    organization_membership_id uuid NOT NULL,
    role integer DEFAULT 0 NOT NULL,
    joined_at timestamp(6) without time zone NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: teams; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.teams (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    name character varying NOT NULL,
    slug character varying NOT NULL,
    created_by_id uuid NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: time_entries; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.time_entries (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    list_item_id uuid NOT NULL,
    user_id uuid NOT NULL,
    duration numeric(10,2) DEFAULT 0.0 NOT NULL,
    started_at timestamp(6) without time zone DEFAULT CURRENT_TIMESTAMP NOT NULL,
    ended_at timestamp(6) without time zone,
    notes text,
    metadata json DEFAULT '{}'::json,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: tool_calls; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tool_calls (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    message_id uuid NOT NULL,
    tool_call_id character varying NOT NULL,
    name character varying NOT NULL,
    arguments jsonb DEFAULT '{}'::jsonb,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: users; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    email character varying NOT NULL,
    name character varying NOT NULL,
    password_digest character varying NOT NULL,
    email_verification_token character varying,
    email_verified_at timestamp(6) without time zone,
    provider character varying,
    uid character varying,
    locale character varying(10) DEFAULT 'en'::character varying NOT NULL,
    timezone character varying(50) DEFAULT 'UTC'::character varying NOT NULL,
    avatar_url character varying,
    bio text,
    status character varying DEFAULT 'active'::character varying NOT NULL,
    last_sign_in_at timestamp(6) without time zone,
    last_sign_in_ip character varying,
    sign_in_count integer DEFAULT 0 NOT NULL,
    discarded_at timestamp(6) without time zone,
    invited_by_admin boolean DEFAULT false,
    suspended_at timestamp(6) without time zone,
    suspended_reason text,
    suspended_by_id uuid,
    deactivated_at timestamp(6) without time zone,
    deactivated_reason text,
    admin_notes text,
    account_metadata jsonb DEFAULT '{}'::jsonb,
    current_organization_id uuid,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: users_roles; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.users_roles (
    user_id uuid,
    role_id uuid
);


--
-- Name: currents id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.currents ALTER COLUMN id SET DEFAULT nextval('public.currents_id_seq'::regclass);


--
-- Name: logidze_data id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.logidze_data ALTER COLUMN id SET DEFAULT nextval('public.logidze_data_id_seq'::regclass);


--
-- Name: models id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.models ALTER COLUMN id SET DEFAULT nextval('public.models_id_seq'::regclass);


--
-- Name: active_storage_attachments active_storage_attachments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT active_storage_attachments_pkey PRIMARY KEY (id);


--
-- Name: active_storage_blobs active_storage_blobs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_blobs
    ADD CONSTRAINT active_storage_blobs_pkey PRIMARY KEY (id);


--
-- Name: active_storage_variant_records active_storage_variant_records_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT active_storage_variant_records_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: board_columns board_columns_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.board_columns
    ADD CONSTRAINT board_columns_pkey PRIMARY KEY (id);


--
-- Name: chats chats_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chats
    ADD CONSTRAINT chats_pkey PRIMARY KEY (id);


--
-- Name: collaborators collaborators_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.collaborators
    ADD CONSTRAINT collaborators_pkey PRIMARY KEY (id);


--
-- Name: comments comments_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT comments_pkey PRIMARY KEY (id);


--
-- Name: currents currents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.currents
    ADD CONSTRAINT currents_pkey PRIMARY KEY (id);


--
-- Name: invitations invitations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT invitations_pkey PRIMARY KEY (id);


--
-- Name: list_items list_items_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.list_items
    ADD CONSTRAINT list_items_pkey PRIMARY KEY (id);


--
-- Name: lists lists_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lists
    ADD CONSTRAINT lists_pkey PRIMARY KEY (id);


--
-- Name: logidze_data logidze_data_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.logidze_data
    ADD CONSTRAINT logidze_data_pkey PRIMARY KEY (id);


--
-- Name: messages messages_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT messages_pkey PRIMARY KEY (id);


--
-- Name: models models_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.models
    ADD CONSTRAINT models_pkey PRIMARY KEY (id);


--
-- Name: noticed_events noticed_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.noticed_events
    ADD CONSTRAINT noticed_events_pkey PRIMARY KEY (id);


--
-- Name: noticed_notifications noticed_notifications_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.noticed_notifications
    ADD CONSTRAINT noticed_notifications_pkey PRIMARY KEY (id);


--
-- Name: notification_settings notification_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_settings
    ADD CONSTRAINT notification_settings_pkey PRIMARY KEY (id);


--
-- Name: organization_memberships organization_memberships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_memberships
    ADD CONSTRAINT organization_memberships_pkey PRIMARY KEY (id);


--
-- Name: organizations organizations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT organizations_pkey PRIMARY KEY (id);


--
-- Name: recovery_contexts recovery_contexts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recovery_contexts
    ADD CONSTRAINT recovery_contexts_pkey PRIMARY KEY (id);


--
-- Name: relationships relationships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.relationships
    ADD CONSTRAINT relationships_pkey PRIMARY KEY (id);


--
-- Name: roles roles_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.roles
    ADD CONSTRAINT roles_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: sessions sessions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT sessions_pkey PRIMARY KEY (id);


--
-- Name: taggings taggings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taggings
    ADD CONSTRAINT taggings_pkey PRIMARY KEY (id);


--
-- Name: tags tags_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tags
    ADD CONSTRAINT tags_pkey PRIMARY KEY (id);


--
-- Name: team_memberships team_memberships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_memberships
    ADD CONSTRAINT team_memberships_pkey PRIMARY KEY (id);


--
-- Name: teams teams_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teams
    ADD CONSTRAINT teams_pkey PRIMARY KEY (id);


--
-- Name: time_entries time_entries_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.time_entries
    ADD CONSTRAINT time_entries_pkey PRIMARY KEY (id);


--
-- Name: tool_calls tool_calls_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tool_calls
    ADD CONSTRAINT tool_calls_pkey PRIMARY KEY (id);


--
-- Name: users users_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT users_pkey PRIMARY KEY (id);


--
-- Name: index_active_storage_attachments_on_blob_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_active_storage_attachments_on_blob_id ON public.active_storage_attachments USING btree (blob_id);


--
-- Name: index_active_storage_attachments_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_attachments_uniqueness ON public.active_storage_attachments USING btree (record_type, record_id, name, blob_id);


--
-- Name: index_active_storage_blobs_on_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_blobs_on_key ON public.active_storage_blobs USING btree (key);


--
-- Name: index_active_storage_variant_records_uniqueness; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_active_storage_variant_records_uniqueness ON public.active_storage_variant_records USING btree (blob_id, variation_digest);


--
-- Name: index_board_columns_on_list_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_board_columns_on_list_id ON public.board_columns USING btree (list_id);


--
-- Name: index_chats_on_conversation_state; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_chats_on_conversation_state ON public.chats USING btree (conversation_state);


--
-- Name: index_chats_on_last_message_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_chats_on_last_message_at ON public.chats USING btree (last_message_at);


--
-- Name: index_chats_on_last_stable_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_chats_on_last_stable_at ON public.chats USING btree (last_stable_at);


--
-- Name: index_chats_on_model_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_chats_on_model_id ON public.chats USING btree (model_id);


--
-- Name: index_chats_on_model_id_string; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_chats_on_model_id_string ON public.chats USING btree (model_id_string);


--
-- Name: index_chats_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_chats_on_user_id ON public.chats USING btree (user_id);


--
-- Name: index_chats_on_user_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_chats_on_user_id_and_created_at ON public.chats USING btree (user_id, created_at);


--
-- Name: index_chats_on_user_id_and_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_chats_on_user_id_and_status ON public.chats USING btree (user_id, status);


--
-- Name: index_collaborators_on_collaboratable; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_collaborators_on_collaboratable ON public.collaborators USING btree (collaboratable_type, collaboratable_id);


--
-- Name: index_collaborators_on_collaboratable_and_user; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_collaborators_on_collaboratable_and_user ON public.collaborators USING btree (collaboratable_id, collaboratable_type, user_id);


--
-- Name: index_collaborators_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_collaborators_on_organization_id ON public.collaborators USING btree (organization_id);


--
-- Name: index_collaborators_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_collaborators_on_user_id ON public.collaborators USING btree (user_id);


--
-- Name: index_comments_on_commentable; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_comments_on_commentable ON public.comments USING btree (commentable_type, commentable_id);


--
-- Name: index_comments_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_comments_on_user_id ON public.comments USING btree (user_id);


--
-- Name: index_invitations_on_email; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invitations_on_email ON public.invitations USING btree (email);


--
-- Name: index_invitations_on_invitable; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invitations_on_invitable ON public.invitations USING btree (invitable_type, invitable_id);


--
-- Name: index_invitations_on_invitable_and_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_invitations_on_invitable_and_email ON public.invitations USING btree (invitable_id, invitable_type, email) WHERE (email IS NOT NULL);


--
-- Name: index_invitations_on_invitable_and_user; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_invitations_on_invitable_and_user ON public.invitations USING btree (invitable_id, invitable_type, user_id) WHERE (user_id IS NOT NULL);


--
-- Name: index_invitations_on_invitation_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_invitations_on_invitation_token ON public.invitations USING btree (invitation_token);


--
-- Name: index_invitations_on_invited_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invitations_on_invited_by_id ON public.invitations USING btree (invited_by_id);


--
-- Name: index_invitations_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invitations_on_organization_id ON public.invitations USING btree (organization_id);


--
-- Name: index_invitations_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invitations_on_status ON public.invitations USING btree (status);


--
-- Name: index_invitations_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_invitations_on_user_id ON public.invitations USING btree (user_id);


--
-- Name: index_list_items_on_assigned_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_list_items_on_assigned_user_id ON public.list_items USING btree (assigned_user_id);


--
-- Name: index_list_items_on_assigned_user_id_and_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_list_items_on_assigned_user_id_and_status ON public.list_items USING btree (assigned_user_id, status);


--
-- Name: index_list_items_on_board_column_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_list_items_on_board_column_id ON public.list_items USING btree (board_column_id);


--
-- Name: index_list_items_on_completed_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_list_items_on_completed_at ON public.list_items USING btree (completed_at);


--
-- Name: index_list_items_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_list_items_on_created_at ON public.list_items USING btree (created_at);


--
-- Name: index_list_items_on_due_date; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_list_items_on_due_date ON public.list_items USING btree (due_date);


--
-- Name: index_list_items_on_due_date_and_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_list_items_on_due_date_and_status ON public.list_items USING btree (due_date, status);


--
-- Name: index_list_items_on_item_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_list_items_on_item_type ON public.list_items USING btree (item_type);


--
-- Name: index_list_items_on_list_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_list_items_on_list_id ON public.list_items USING btree (list_id);


--
-- Name: index_list_items_on_list_id_and_position; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_list_items_on_list_id_and_position ON public.list_items USING btree (list_id, "position");


--
-- Name: index_list_items_on_list_id_and_priority; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_list_items_on_list_id_and_priority ON public.list_items USING btree (list_id, priority);


--
-- Name: index_list_items_on_list_id_and_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_list_items_on_list_id_and_status ON public.list_items USING btree (list_id, status);


--
-- Name: index_list_items_on_position; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_list_items_on_position ON public.list_items USING btree ("position");


--
-- Name: index_list_items_on_priority; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_list_items_on_priority ON public.list_items USING btree (priority);


--
-- Name: index_list_items_on_skip_notifications; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_list_items_on_skip_notifications ON public.list_items USING btree (skip_notifications);


--
-- Name: index_list_items_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_list_items_on_status ON public.list_items USING btree (status);


--
-- Name: index_lists_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lists_on_created_at ON public.lists USING btree (created_at);


--
-- Name: index_lists_on_is_public; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lists_on_is_public ON public.lists USING btree (is_public);


--
-- Name: index_lists_on_list_collaborations_count; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lists_on_list_collaborations_count ON public.lists USING btree (list_collaborations_count);


--
-- Name: index_lists_on_list_items_count; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lists_on_list_items_count ON public.lists USING btree (list_items_count);


--
-- Name: index_lists_on_list_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lists_on_list_type ON public.lists USING btree (list_type);


--
-- Name: index_lists_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lists_on_organization_id ON public.lists USING btree (organization_id);


--
-- Name: index_lists_on_parent_list_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lists_on_parent_list_id ON public.lists USING btree (parent_list_id);


--
-- Name: index_lists_on_parent_list_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lists_on_parent_list_id_and_created_at ON public.lists USING btree (parent_list_id, created_at);


--
-- Name: index_lists_on_public_permission; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lists_on_public_permission ON public.lists USING btree (public_permission);


--
-- Name: index_lists_on_public_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_lists_on_public_slug ON public.lists USING btree (public_slug);


--
-- Name: index_lists_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lists_on_status ON public.lists USING btree (status);


--
-- Name: index_lists_on_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lists_on_team_id ON public.lists USING btree (team_id);


--
-- Name: index_lists_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lists_on_user_id ON public.lists USING btree (user_id);


--
-- Name: index_lists_on_user_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lists_on_user_id_and_created_at ON public.lists USING btree (user_id, created_at);


--
-- Name: index_lists_on_user_id_and_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lists_on_user_id_and_status ON public.lists USING btree (user_id, status);


--
-- Name: index_lists_on_user_is_public; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lists_on_user_is_public ON public.lists USING btree (user_id, is_public);


--
-- Name: index_lists_on_user_list_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lists_on_user_list_type ON public.lists USING btree (user_id, list_type);


--
-- Name: index_lists_on_user_parent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lists_on_user_parent ON public.lists USING btree (user_id, parent_list_id);


--
-- Name: index_lists_on_user_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lists_on_user_status ON public.lists USING btree (user_id, status);


--
-- Name: index_lists_on_user_status_list_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lists_on_user_status_list_type ON public.lists USING btree (user_id, status, list_type);


--
-- Name: index_logidze_loggable; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_logidze_loggable ON public.logidze_data USING btree (loggable_type, loggable_id);


--
-- Name: index_messages_on_chat_and_tool_call_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_messages_on_chat_and_tool_call_id ON public.messages USING btree (chat_id, tool_call_id) WHERE (tool_call_id IS NOT NULL);


--
-- Name: index_messages_on_chat_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_messages_on_chat_id ON public.messages USING btree (chat_id);


--
-- Name: index_messages_on_chat_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_messages_on_chat_id_and_created_at ON public.messages USING btree (chat_id, created_at);


--
-- Name: index_messages_on_chat_id_and_role; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_messages_on_chat_id_and_role ON public.messages USING btree (chat_id, role);


--
-- Name: index_messages_on_chat_id_and_role_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_messages_on_chat_id_and_role_and_created_at ON public.messages USING btree (chat_id, role, created_at);


--
-- Name: index_messages_on_chat_id_and_tool_call_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_messages_on_chat_id_and_tool_call_id ON public.messages USING btree (chat_id, tool_call_id) WHERE (tool_call_id IS NOT NULL);


--
-- Name: index_messages_on_llm_provider_and_llm_model; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_messages_on_llm_provider_and_llm_model ON public.messages USING btree (llm_provider, llm_model);


--
-- Name: index_messages_on_message_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_messages_on_message_type ON public.messages USING btree (message_type);


--
-- Name: index_messages_on_model_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_messages_on_model_id ON public.messages USING btree (model_id);


--
-- Name: index_messages_on_model_id_string; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_messages_on_model_id_string ON public.messages USING btree (model_id_string);


--
-- Name: index_messages_on_role; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_messages_on_role ON public.messages USING btree (role);


--
-- Name: index_messages_on_role_and_tool_call_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_messages_on_role_and_tool_call_id ON public.messages USING btree (role, tool_call_id) WHERE (((role)::text = 'tool'::text) AND (tool_call_id IS NOT NULL));


--
-- Name: index_messages_on_tool_call_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_messages_on_tool_call_id ON public.messages USING btree (tool_call_id);


--
-- Name: index_messages_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_messages_on_user_id ON public.messages USING btree (user_id);


--
-- Name: index_messages_on_user_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_messages_on_user_id_and_created_at ON public.messages USING btree (user_id, created_at);


--
-- Name: index_messages_unique_tool_call_id_per_chat; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_messages_unique_tool_call_id_per_chat ON public.messages USING btree (chat_id, tool_call_id) WHERE (((role)::text = 'tool'::text) AND (tool_call_id IS NOT NULL));


--
-- Name: index_models_on_capabilities; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_models_on_capabilities ON public.models USING gin (capabilities);


--
-- Name: index_models_on_family; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_models_on_family ON public.models USING btree (family);


--
-- Name: index_models_on_modalities; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_models_on_modalities ON public.models USING gin (modalities);


--
-- Name: index_models_on_provider; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_models_on_provider ON public.models USING btree (provider);


--
-- Name: index_models_on_provider_and_model_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_models_on_provider_and_model_id ON public.models USING btree (provider, model_id);


--
-- Name: index_noticed_events_on_record; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_noticed_events_on_record ON public.noticed_events USING btree (record_type, record_id);


--
-- Name: index_noticed_notifications_on_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_noticed_notifications_on_event_id ON public.noticed_notifications USING btree (event_id);


--
-- Name: index_noticed_notifications_on_recipient; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_noticed_notifications_on_recipient ON public.noticed_notifications USING btree (recipient_type, recipient_id);


--
-- Name: index_notification_settings_on_notification_frequency; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notification_settings_on_notification_frequency ON public.notification_settings USING btree (notification_frequency);


--
-- Name: index_notification_settings_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_notification_settings_on_user_id ON public.notification_settings USING btree (user_id);


--
-- Name: index_organization_memberships_on_joined_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_organization_memberships_on_joined_at ON public.organization_memberships USING btree (joined_at);


--
-- Name: index_organization_memberships_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_organization_memberships_on_organization_id ON public.organization_memberships USING btree (organization_id);


--
-- Name: index_organization_memberships_on_organization_id_and_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_organization_memberships_on_organization_id_and_user_id ON public.organization_memberships USING btree (organization_id, user_id);


--
-- Name: index_organization_memberships_on_role; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_organization_memberships_on_role ON public.organization_memberships USING btree (role);


--
-- Name: index_organization_memberships_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_organization_memberships_on_status ON public.organization_memberships USING btree (status);


--
-- Name: index_organization_memberships_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_organization_memberships_on_user_id ON public.organization_memberships USING btree (user_id);


--
-- Name: index_organizations_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_organizations_on_created_at ON public.organizations USING btree (created_at);


--
-- Name: index_organizations_on_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_organizations_on_created_by_id ON public.organizations USING btree (created_by_id);


--
-- Name: index_organizations_on_size; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_organizations_on_size ON public.organizations USING btree (size);


--
-- Name: index_organizations_on_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_organizations_on_slug ON public.organizations USING btree (slug);


--
-- Name: index_organizations_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_organizations_on_status ON public.organizations USING btree (status);


--
-- Name: index_recovery_contexts_on_chat_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_recovery_contexts_on_chat_id ON public.recovery_contexts USING btree (chat_id);


--
-- Name: index_recovery_contexts_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_recovery_contexts_on_created_at ON public.recovery_contexts USING btree (created_at);


--
-- Name: index_recovery_contexts_on_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_recovery_contexts_on_expires_at ON public.recovery_contexts USING btree (expires_at);


--
-- Name: index_recovery_contexts_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_recovery_contexts_on_user_id ON public.recovery_contexts USING btree (user_id);


--
-- Name: index_recovery_contexts_on_user_id_and_chat_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_recovery_contexts_on_user_id_and_chat_id ON public.recovery_contexts USING btree (user_id, chat_id);


--
-- Name: index_relationships_on_child; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_relationships_on_child ON public.relationships USING btree (child_type, child_id);


--
-- Name: index_relationships_on_parent; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_relationships_on_parent ON public.relationships USING btree (parent_type, parent_id);


--
-- Name: index_relationships_on_parent_and_child; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_relationships_on_parent_and_child ON public.relationships USING btree (parent_id, parent_type, child_id, child_type);


--
-- Name: index_roles_on_name_and_resource_type_and_resource_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_roles_on_name_and_resource_type_and_resource_id ON public.roles USING btree (name, resource_type, resource_id);


--
-- Name: index_roles_on_resource; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_roles_on_resource ON public.roles USING btree (resource_type, resource_id);


--
-- Name: index_sessions_on_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sessions_on_expires_at ON public.sessions USING btree (expires_at);


--
-- Name: index_sessions_on_session_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_sessions_on_session_token ON public.sessions USING btree (session_token);


--
-- Name: index_sessions_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sessions_on_user_id ON public.sessions USING btree (user_id);


--
-- Name: index_sessions_on_user_id_and_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_sessions_on_user_id_and_expires_at ON public.sessions USING btree (user_id, expires_at);


--
-- Name: index_taggings_on_context; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_taggings_on_context ON public.taggings USING btree (context);


--
-- Name: index_taggings_on_tag_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_taggings_on_tag_id ON public.taggings USING btree (tag_id);


--
-- Name: index_taggings_on_taggable_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_taggings_on_taggable_id ON public.taggings USING btree (taggable_id);


--
-- Name: index_taggings_on_taggable_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_taggings_on_taggable_type ON public.taggings USING btree (taggable_type);


--
-- Name: index_taggings_on_taggable_type_and_taggable_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_taggings_on_taggable_type_and_taggable_id ON public.taggings USING btree (taggable_type, taggable_id);


--
-- Name: index_taggings_on_tagger_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_taggings_on_tagger_id ON public.taggings USING btree (tagger_id);


--
-- Name: index_taggings_on_tagger_id_and_tagger_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_taggings_on_tagger_id_and_tagger_type ON public.taggings USING btree (tagger_id, tagger_type);


--
-- Name: index_taggings_on_tagger_type_and_tagger_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_taggings_on_tagger_type_and_tagger_id ON public.taggings USING btree (tagger_type, tagger_id);


--
-- Name: index_taggings_on_tenant; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_taggings_on_tenant ON public.taggings USING btree (tenant);


--
-- Name: index_tags_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_tags_on_name ON public.tags USING btree (name);


--
-- Name: index_team_memberships_on_joined_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_team_memberships_on_joined_at ON public.team_memberships USING btree (joined_at);


--
-- Name: index_team_memberships_on_organization_membership_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_team_memberships_on_organization_membership_id ON public.team_memberships USING btree (organization_membership_id);


--
-- Name: index_team_memberships_on_role; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_team_memberships_on_role ON public.team_memberships USING btree (role);


--
-- Name: index_team_memberships_on_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_team_memberships_on_team_id ON public.team_memberships USING btree (team_id);


--
-- Name: index_team_memberships_on_team_id_and_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_team_memberships_on_team_id_and_user_id ON public.team_memberships USING btree (team_id, user_id);


--
-- Name: index_team_memberships_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_team_memberships_on_user_id ON public.team_memberships USING btree (user_id);


--
-- Name: index_teams_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_teams_on_created_at ON public.teams USING btree (created_at);


--
-- Name: index_teams_on_created_by_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_teams_on_created_by_id ON public.teams USING btree (created_by_id);


--
-- Name: index_teams_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_teams_on_organization_id ON public.teams USING btree (organization_id);


--
-- Name: index_teams_on_organization_id_and_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_teams_on_organization_id_and_slug ON public.teams USING btree (organization_id, slug);


--
-- Name: index_tool_calls_on_message_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tool_calls_on_message_id ON public.tool_calls USING btree (message_id);


--
-- Name: index_tool_calls_on_message_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tool_calls_on_message_id_and_created_at ON public.tool_calls USING btree (message_id, created_at);


--
-- Name: index_tool_calls_on_name; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tool_calls_on_name ON public.tool_calls USING btree (name);


--
-- Name: index_tool_calls_on_tool_call_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_tool_calls_on_tool_call_id ON public.tool_calls USING btree (tool_call_id);


--
-- Name: index_users_on_account_metadata; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_account_metadata ON public.users USING gin (account_metadata);


--
-- Name: index_users_on_current_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_current_organization_id ON public.users USING btree (current_organization_id);


--
-- Name: index_users_on_deactivated_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_deactivated_at ON public.users USING btree (deactivated_at);


--
-- Name: index_users_on_discarded_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_discarded_at ON public.users USING btree (discarded_at);


--
-- Name: index_users_on_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_email ON public.users USING btree (email);


--
-- Name: index_users_on_email_verification_token; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_email_verification_token ON public.users USING btree (email_verification_token);


--
-- Name: index_users_on_invited_by_admin; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_invited_by_admin ON public.users USING btree (invited_by_admin);


--
-- Name: index_users_on_last_sign_in_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_last_sign_in_at ON public.users USING btree (last_sign_in_at);


--
-- Name: index_users_on_locale; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_locale ON public.users USING btree (locale);


--
-- Name: index_users_on_provider_and_uid; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_users_on_provider_and_uid ON public.users USING btree (provider, uid);


--
-- Name: index_users_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_status ON public.users USING btree (status);


--
-- Name: index_users_on_suspended_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_suspended_at ON public.users USING btree (suspended_at);


--
-- Name: index_users_on_timezone; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_on_timezone ON public.users USING btree (timezone);


--
-- Name: index_users_roles_on_role_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_roles_on_role_id ON public.users_roles USING btree (role_id);


--
-- Name: index_users_roles_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_roles_on_user_id ON public.users_roles USING btree (user_id);


--
-- Name: index_users_roles_on_user_id_and_role_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_users_roles_on_user_id_and_role_id ON public.users_roles USING btree (user_id, role_id);


--
-- Name: taggings_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX taggings_idx ON public.taggings USING btree (tag_id, taggable_id, taggable_type, context, tagger_id, tagger_type);


--
-- Name: taggings_idy; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX taggings_idy ON public.taggings USING btree (taggable_id, taggable_type, tagger_id, context);


--
-- Name: taggings_taggable_context_idx; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX taggings_taggable_context_idx ON public.taggings USING btree (taggable_id, taggable_type, context);


--
-- Name: board_columns fk_rails_03d1189c1d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.board_columns
    ADD CONSTRAINT fk_rails_03d1189c1d FOREIGN KEY (list_id) REFERENCES public.lists(id);


--
-- Name: comments fk_rails_03de2dc08c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.comments
    ADD CONSTRAINT fk_rails_03de2dc08c FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: notification_settings fk_rails_0c95e91db7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.notification_settings
    ADD CONSTRAINT fk_rails_0c95e91db7 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: messages fk_rails_0f670de7ba; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT fk_rails_0f670de7ba FOREIGN KEY (chat_id) REFERENCES public.chats(id);


--
-- Name: list_items fk_rails_12b8df7bb8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.list_items
    ADD CONSTRAINT fk_rails_12b8df7bb8 FOREIGN KEY (list_id) REFERENCES public.lists(id);


--
-- Name: chats fk_rails_1835d93df1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chats
    ADD CONSTRAINT fk_rails_1835d93df1 FOREIGN KEY (model_id) REFERENCES public.models(id);


--
-- Name: messages fk_rails_273a25a7a6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT fk_rails_273a25a7a6 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: collaborators fk_rails_3d4aaacbb1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.collaborators
    ADD CONSTRAINT fk_rails_3d4aaacbb1 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: recovery_contexts fk_rails_51e01bf1ba; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recovery_contexts
    ADD CONSTRAINT fk_rails_51e01bf1ba FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: organization_memberships fk_rails_57cf70d280; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_memberships
    ADD CONSTRAINT fk_rails_57cf70d280 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: team_memberships fk_rails_5aba9331a7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_memberships
    ADD CONSTRAINT fk_rails_5aba9331a7 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: team_memberships fk_rails_61c29b529e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_memberships
    ADD CONSTRAINT fk_rails_61c29b529e FOREIGN KEY (team_id) REFERENCES public.teams(id);


--
-- Name: list_items fk_rails_671dc678fa; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.list_items
    ADD CONSTRAINT fk_rails_671dc678fa FOREIGN KEY (board_column_id) REFERENCES public.board_columns(id);


--
-- Name: team_memberships fk_rails_6dfe318707; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_memberships
    ADD CONSTRAINT fk_rails_6dfe318707 FOREIGN KEY (organization_membership_id) REFERENCES public.organization_memberships(id);


--
-- Name: organization_memberships fk_rails_715ab7f4fe; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_memberships
    ADD CONSTRAINT fk_rails_715ab7f4fe FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: sessions fk_rails_758836b4f0; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.sessions
    ADD CONSTRAINT fk_rails_758836b4f0 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: invitations fk_rails_7eae413fe6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT fk_rails_7eae413fe6 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: list_items fk_rails_7f2175ff1c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.list_items
    ADD CONSTRAINT fk_rails_7f2175ff1c FOREIGN KEY (assigned_user_id) REFERENCES public.users(id);


--
-- Name: active_storage_variant_records fk_rails_993965df05; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT fk_rails_993965df05 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: tool_calls fk_rails_9c8daee481; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tool_calls
    ADD CONSTRAINT fk_rails_9c8daee481 FOREIGN KEY (message_id) REFERENCES public.messages(id);


--
-- Name: taggings fk_rails_9fcd2e236b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taggings
    ADD CONSTRAINT fk_rails_9fcd2e236b FOREIGN KEY (tag_id) REFERENCES public.tags(id);


--
-- Name: teams fk_rails_a068b3a692; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teams
    ADD CONSTRAINT fk_rails_a068b3a692 FOREIGN KEY (created_by_id) REFERENCES public.users(id);


--
-- Name: lists fk_rails_beaf740ad9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lists
    ADD CONSTRAINT fk_rails_beaf740ad9 FOREIGN KEY (parent_list_id) REFERENCES public.lists(id);


--
-- Name: messages fk_rails_c02b47ad97; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT fk_rails_c02b47ad97 FOREIGN KEY (model_id) REFERENCES public.models(id);


--
-- Name: active_storage_attachments fk_rails_c3b3935057; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT fk_rails_c3b3935057 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: users fk_rails_d5e043db78; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT fk_rails_d5e043db78 FOREIGN KEY (suspended_by_id) REFERENCES public.users(id);


--
-- Name: lists fk_rails_d6cf4279f7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.lists
    ADD CONSTRAINT fk_rails_d6cf4279f7 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: invitations fk_rails_d799c974a1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.invitations
    ADD CONSTRAINT fk_rails_d799c974a1 FOREIGN KEY (invited_by_id) REFERENCES public.users(id);


--
-- Name: chats fk_rails_e555f43151; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chats
    ADD CONSTRAINT fk_rails_e555f43151 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: organizations fk_rails_edec76c076; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organizations
    ADD CONSTRAINT fk_rails_edec76c076 FOREIGN KEY (created_by_id) REFERENCES public.users(id);


--
-- Name: teams fk_rails_f07f0bd66d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teams
    ADD CONSTRAINT fk_rails_f07f0bd66d FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: recovery_contexts fk_rails_f37be66aa7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recovery_contexts
    ADD CONSTRAINT fk_rails_f37be66aa7 FOREIGN KEY (chat_id) REFERENCES public.chats(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20251206170353'),
('20251115200022'),
('20251115200021'),
('20251115200020'),
('20251115200019'),
('20251103202838'),
('20251011000104'),
('20251010235748'),
('20251010235747'),
('20250910233319'),
('20250730204201'),
('20250723185557'),
('20250707182418'),
('20250707014433'),
('20250706232534'),
('20250706232527'),
('20250706232521'),
('20250706232511'),
('20250706232501'),
('20250706232451'),
('20250706224556'),
('20250706224547'),
('20250706224546'),
('20250706224545'),
('20250706224544'),
('20250706224543'),
('20250706224542'),
('20250706224541'),
('20250703034216'),
('20250630212045'),
('20250628043943'),
('20250628004955'),
('20250628004938'),
('20250628004925'),
('20250624223654'),
('20250624223653'),
('20250623211535'),
('20250623211119'),
('20250623211117'),
('20250623100332'),
('20250623083443'),
('20250623083440');

