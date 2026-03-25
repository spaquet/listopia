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
-- Name: vector; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS vector WITH SCHEMA public;


--
-- Name: EXTENSION vector; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION vector IS 'vector data type and ivfflat and hnsw access methods';


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
-- Name: ai_agent_feedbacks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ai_agent_feedbacks (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    ai_agent_run_id uuid NOT NULL,
    ai_agent_id uuid NOT NULL,
    user_id uuid NOT NULL,
    rating integer NOT NULL,
    feedback_type integer,
    helpfulness_score integer,
    comment text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: ai_agent_resources; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ai_agent_resources (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    ai_agent_id uuid NOT NULL,
    resource_type character varying NOT NULL,
    resource_identifier character varying,
    permission integer DEFAULT 0 NOT NULL,
    description text,
    config jsonb DEFAULT '"{}"'::jsonb NOT NULL,
    enabled boolean DEFAULT true NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: ai_agent_run_steps; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ai_agent_run_steps (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    ai_agent_run_id uuid NOT NULL,
    step_number integer NOT NULL,
    step_type character varying NOT NULL,
    title character varying,
    description text,
    status integer DEFAULT 0 NOT NULL,
    prompt_sent text,
    response_received text,
    tool_name character varying,
    tool_input jsonb DEFAULT '"{}"'::jsonb NOT NULL,
    tool_output jsonb DEFAULT '"{}"'::jsonb NOT NULL,
    input_tokens integer DEFAULT 0,
    output_tokens integer DEFAULT 0,
    processing_time_ms integer,
    error_message text,
    started_at timestamp(6) without time zone,
    completed_at timestamp(6) without time zone,
    metadata jsonb DEFAULT '"{}"'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: ai_agent_runs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ai_agent_runs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    ai_agent_id uuid NOT NULL,
    user_id uuid NOT NULL,
    organization_id uuid NOT NULL,
    invocable_type character varying,
    invocable_id uuid,
    parent_run_id uuid,
    status integer DEFAULT 0 NOT NULL,
    user_input text,
    input_parameters jsonb DEFAULT '"{}"'::jsonb NOT NULL,
    result_summary text,
    result_data jsonb DEFAULT '"{}"'::jsonb NOT NULL,
    input_tokens integer DEFAULT 0,
    output_tokens integer DEFAULT 0,
    thinking_tokens integer DEFAULT 0,
    total_tokens integer DEFAULT 0,
    processing_time_ms integer,
    steps_completed integer DEFAULT 0,
    steps_total integer DEFAULT 0,
    error_message text,
    cancellation_reason text,
    started_at timestamp(6) without time zone,
    completed_at timestamp(6) without time zone,
    paused_at timestamp(6) without time zone,
    last_activity_at timestamp(6) without time zone,
    metadata jsonb DEFAULT '"{}"'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: ai_agent_team_memberships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ai_agent_team_memberships (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    ai_agent_id uuid NOT NULL,
    team_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: ai_agents; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ai_agents (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    name character varying NOT NULL,
    description text,
    slug character varying NOT NULL,
    scope integer DEFAULT 0 NOT NULL,
    user_id uuid,
    organization_id uuid,
    prompt text NOT NULL,
    parameters jsonb DEFAULT '"{}"'::jsonb NOT NULL,
    status integer DEFAULT 0 NOT NULL,
    max_tokens_per_run integer DEFAULT 4000,
    max_tokens_per_day integer DEFAULT 50000,
    max_tokens_per_month integer DEFAULT 500000,
    timeout_seconds integer DEFAULT 120,
    max_steps integer DEFAULT 20,
    rate_limit_per_hour integer DEFAULT 10,
    tokens_used_today integer DEFAULT 0,
    tokens_used_this_month integer DEFAULT 0,
    tokens_today_date date,
    tokens_month_year integer,
    model character varying DEFAULT 'gpt-4o-mini'::character varying,
    metadata jsonb DEFAULT '"{}"'::jsonb NOT NULL,
    run_count integer DEFAULT 0,
    success_count integer DEFAULT 0,
    average_rating double precision,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    discarded_at timestamp(6) without time zone
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
-- Name: attendee_contacts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.attendee_contacts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    organization_id uuid NOT NULL,
    user_id uuid,
    email character varying NOT NULL,
    display_name character varying,
    title character varying,
    company character varying,
    location character varying,
    bio text,
    avatar_url character varying,
    linkedin_url character varying,
    github_username character varying,
    twitter_url character varying,
    website_url character varying,
    linkedin_data jsonb,
    github_data jsonb,
    clearbit_data jsonb,
    enrichment_status character varying DEFAULT 'pending'::character varying,
    enriched_at timestamp(6) without time zone,
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
-- Name: calendar_events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.calendar_events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    organization_id uuid NOT NULL,
    connector_account_id uuid,
    external_event_id character varying NOT NULL,
    provider character varying NOT NULL,
    summary character varying NOT NULL,
    description text,
    start_time timestamp with time zone NOT NULL,
    end_time timestamp with time zone,
    status character varying DEFAULT 'confirmed'::character varying,
    timezone character varying,
    attendees jsonb DEFAULT '[]'::jsonb NOT NULL,
    organizer_email character varying,
    organizer_name character varying,
    is_organizer boolean DEFAULT false,
    embedding public.vector(1536),
    embedding_generated_at timestamp(6) without time zone,
    requires_embedding_update boolean DEFAULT false NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    external_event_url character varying
);


--
-- Name: chat_contexts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.chat_contexts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    chat_id uuid NOT NULL,
    organization_id uuid NOT NULL,
    state character varying DEFAULT 'initial'::character varying NOT NULL,
    status character varying DEFAULT 'pending'::character varying NOT NULL,
    request_content text,
    detected_intent character varying,
    planning_domain character varying,
    is_complex boolean DEFAULT false,
    complexity_level character varying,
    complexity_reasoning text,
    parameters jsonb DEFAULT '{}'::jsonb,
    pre_creation_questions jsonb DEFAULT '[]'::jsonb,
    pre_creation_answers jsonb DEFAULT '{}'::jsonb,
    hierarchical_items jsonb DEFAULT '{}'::jsonb,
    generated_items jsonb DEFAULT '[]'::jsonb,
    missing_parameters character varying[] DEFAULT '{}'::character varying[],
    list_created_id uuid,
    post_creation_mode boolean DEFAULT false,
    last_activity_at timestamp(6) without time zone,
    recovery_checkpoint jsonb DEFAULT '{}'::jsonb,
    metadata jsonb DEFAULT '{}'::jsonb,
    error_message text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    intent_confidence double precision DEFAULT 0.0,
    parent_requirements jsonb DEFAULT '{}'::jsonb
);


--
-- Name: COLUMN chat_contexts.state; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.chat_contexts.state IS 'State: initial, pre_creation, resource_creation, completed';


--
-- Name: COLUMN chat_contexts.status; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.chat_contexts.status IS 'Status: pending, analyzing, awaiting_user_input, processing, complete, error';


--
-- Name: COLUMN chat_contexts.request_content; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.chat_contexts.request_content IS 'Original user request';


--
-- Name: COLUMN chat_contexts.detected_intent; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.chat_contexts.detected_intent IS 'Detected intent: create_list, navigate_to_page, etc.';


--
-- Name: COLUMN chat_contexts.planning_domain; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.chat_contexts.planning_domain IS 'Domain: vacation, sprint, roadshow, etc.';


--
-- Name: COLUMN chat_contexts.is_complex; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.chat_contexts.is_complex IS 'Whether request is complex and needs clarifying questions';


--
-- Name: COLUMN chat_contexts.complexity_level; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.chat_contexts.complexity_level IS 'simple, complex';


--
-- Name: COLUMN chat_contexts.complexity_reasoning; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.chat_contexts.complexity_reasoning IS 'Why the request was classified as simple or complex';


--
-- Name: COLUMN chat_contexts.parameters; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.chat_contexts.parameters IS 'Extracted parameters from request';


--
-- Name: COLUMN chat_contexts.pre_creation_questions; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.chat_contexts.pre_creation_questions IS 'Clarifying questions for complex lists';


--
-- Name: COLUMN chat_contexts.pre_creation_answers; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.chat_contexts.pre_creation_answers IS 'User''s answers to pre-creation questions';


--
-- Name: COLUMN chat_contexts.hierarchical_items; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.chat_contexts.hierarchical_items IS 'Parent items, subdivisions, subdivision type for nested lists';


--
-- Name: COLUMN chat_contexts.generated_items; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.chat_contexts.generated_items IS 'Generated items';


--
-- Name: COLUMN chat_contexts.missing_parameters; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.chat_contexts.missing_parameters IS 'Parameters missing from request';


--
-- Name: COLUMN chat_contexts.list_created_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.chat_contexts.list_created_id IS 'ID of the created list';


--
-- Name: COLUMN chat_contexts.post_creation_mode; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.chat_contexts.post_creation_mode IS 'True when showing ''keep or clear context'' buttons after list creation';


--
-- Name: COLUMN chat_contexts.last_activity_at; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.chat_contexts.last_activity_at IS 'Timestamp of last interaction; used for connection recovery';


--
-- Name: COLUMN chat_contexts.recovery_checkpoint; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.chat_contexts.recovery_checkpoint IS 'Last known good state snapshot for crash recovery';


--
-- Name: COLUMN chat_contexts.metadata; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.chat_contexts.metadata IS 'Additional metadata and performance metrics (thinking_tokens, generation_time_ms, etc.)';


--
-- Name: COLUMN chat_contexts.error_message; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.chat_contexts.error_message IS 'Error message if status is error';


--
-- Name: COLUMN chat_contexts.intent_confidence; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.chat_contexts.intent_confidence IS 'Confidence score for intent detection (0.0-1.0)';


--
-- Name: COLUMN chat_contexts.parent_requirements; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.chat_contexts.parent_requirements IS 'Parent item requirements extracted from planning domain';


--
-- Name: chats; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.chats (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    model_id bigint,
    conversation_state character varying DEFAULT 'stable'::character varying,
    last_cleanup_at timestamp(6) without time zone,
    user_id uuid NOT NULL,
    title character varying(255),
    context json DEFAULT '{}'::json,
    status character varying DEFAULT 'active'::character varying,
    last_message_at timestamp(6) without time zone,
    metadata json DEFAULT '{}'::json,
    model_id_string character varying,
    last_stable_at timestamp(6) without time zone,
    organization_id uuid,
    team_id uuid,
    visibility character varying DEFAULT 'private'::character varying,
    focused_resource_type character varying,
    focused_resource_id uuid,
    chat_context_id uuid
);


--
-- Name: COLUMN chats.chat_context_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.chats.chat_context_id IS 'Reference to the chat context';


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
    updated_at timestamp(6) without time zone NOT NULL,
    embedding public.vector,
    embedding_generated_at timestamp(6) without time zone,
    requires_embedding_update boolean DEFAULT false,
    search_document tsvector
);


--
-- Name: connector_accounts; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.connector_accounts (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    user_id uuid NOT NULL,
    organization_id uuid NOT NULL,
    provider character varying NOT NULL,
    provider_uid character varying NOT NULL,
    display_name character varying,
    email character varying,
    access_token_encrypted text,
    refresh_token_encrypted text,
    token_expires_at timestamp with time zone,
    token_scope character varying,
    status character varying DEFAULT 'active'::character varying NOT NULL,
    last_sync_at timestamp with time zone,
    last_error text,
    error_count integer DEFAULT 0 NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: connector_event_mappings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.connector_event_mappings (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    connector_account_id uuid NOT NULL,
    external_id character varying NOT NULL,
    external_type character varying NOT NULL,
    local_type character varying NOT NULL,
    local_id uuid,
    sync_direction character varying DEFAULT 'both'::character varying NOT NULL,
    last_synced_at timestamp with time zone,
    external_etag character varying,
    metadata jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: connector_settings; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.connector_settings (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    connector_account_id uuid NOT NULL,
    key character varying NOT NULL,
    value text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: connector_sync_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.connector_sync_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    connector_account_id uuid NOT NULL,
    operation character varying NOT NULL,
    status character varying NOT NULL,
    records_processed integer DEFAULT 0,
    records_created integer DEFAULT 0,
    records_updated integer DEFAULT 0,
    records_failed integer DEFAULT 0,
    error_message text,
    duration_ms integer,
    started_at timestamp with time zone,
    completed_at timestamp with time zone,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: connector_webhook_subscriptions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.connector_webhook_subscriptions (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    connector_account_id uuid NOT NULL,
    provider character varying NOT NULL,
    calendar_id character varying NOT NULL,
    subscription_id character varying NOT NULL,
    resource_id character varying,
    channel_token character varying,
    expires_at timestamp with time zone,
    status character varying DEFAULT 'active'::character varying,
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
-- Name: events; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.events (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    event_type character varying NOT NULL,
    actor_id uuid,
    event_data jsonb DEFAULT '{}'::jsonb,
    organization_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


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
    completed_at timestamp(6) without time zone,
    embedding public.vector,
    embedding_generated_at timestamp(6) without time zone,
    requires_embedding_update boolean DEFAULT false,
    search_document tsvector
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
    list_collaborations_count integer DEFAULT 0 NOT NULL,
    embedding public.vector,
    embedding_generated_at timestamp(6) without time zone,
    requires_embedding_update boolean DEFAULT false,
    search_document tsvector
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
-- Name: message_feedbacks; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.message_feedbacks (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    message_id uuid NOT NULL,
    user_id uuid NOT NULL,
    chat_id uuid NOT NULL,
    rating integer NOT NULL,
    feedback_type integer,
    comment text,
    helpfulness_score integer,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: messages; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.messages (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    role character varying NOT NULL,
    content text,
    content_raw json,
    input_tokens integer,
    output_tokens integer,
    cached_tokens integer,
    cache_creation_tokens integer,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    chat_id uuid NOT NULL,
    model_id bigint,
    tool_call_id uuid,
    user_id uuid,
    message_type character varying DEFAULT 'text'::character varying,
    metadata json DEFAULT '{}'::json,
    context_snapshot json DEFAULT '{}'::json,
    llm_provider character varying,
    llm_model character varying,
    model_id_string character varying,
    token_count integer,
    processing_time numeric(8,3),
    organization_id uuid,
    template_type character varying,
    blocked boolean DEFAULT false,
    thinking_text text,
    thinking_signature text,
    thinking_tokens integer
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
-- Name: moderation_logs; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.moderation_logs (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    chat_id uuid,
    message_id uuid,
    user_id uuid,
    organization_id uuid,
    violation_type integer DEFAULT 0,
    action_taken integer DEFAULT 0,
    detected_patterns jsonb DEFAULT '[]'::jsonb,
    moderation_scores jsonb DEFAULT '{}'::jsonb,
    prompt_injection_risk character varying DEFAULT 'low'::character varying,
    details text,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


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
-- Name: planning_relationships; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.planning_relationships (
    id uuid DEFAULT gen_random_uuid() NOT NULL,
    chat_context_id uuid NOT NULL,
    parent_type character varying NOT NULL,
    child_type character varying NOT NULL,
    relationship_type character varying NOT NULL,
    metadata jsonb DEFAULT '{}'::jsonb,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: COLUMN planning_relationships.chat_context_id; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.planning_relationships.chat_context_id IS 'Reference to the planning context';


--
-- Name: COLUMN planning_relationships.parent_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.planning_relationships.parent_type IS 'Type of parent item';


--
-- Name: COLUMN planning_relationships.child_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.planning_relationships.child_type IS 'Type of child item';


--
-- Name: COLUMN planning_relationships.relationship_type; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.planning_relationships.relationship_type IS 'Type of relationship (hierarchy, dependency, etc.)';


--
-- Name: COLUMN planning_relationships.metadata; Type: COMMENT; Schema: public; Owner: -
--

COMMENT ON COLUMN public.planning_relationships.metadata IS 'Additional relationship metadata';


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
    taggings_count integer DEFAULT 0,
    embedding public.vector,
    embedding_generated_at timestamp(6) without time zone,
    requires_embedding_update boolean DEFAULT false,
    search_document tsvector
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
    tool_call_id character varying NOT NULL,
    name character varying NOT NULL,
    arguments jsonb DEFAULT '{}'::jsonb,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL,
    message_id uuid NOT NULL,
    thought_signature text
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
-- Name: ai_agent_feedbacks ai_agent_feedbacks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_agent_feedbacks
    ADD CONSTRAINT ai_agent_feedbacks_pkey PRIMARY KEY (id);


--
-- Name: ai_agent_resources ai_agent_resources_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_agent_resources
    ADD CONSTRAINT ai_agent_resources_pkey PRIMARY KEY (id);


--
-- Name: ai_agent_run_steps ai_agent_run_steps_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_agent_run_steps
    ADD CONSTRAINT ai_agent_run_steps_pkey PRIMARY KEY (id);


--
-- Name: ai_agent_runs ai_agent_runs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_agent_runs
    ADD CONSTRAINT ai_agent_runs_pkey PRIMARY KEY (id);


--
-- Name: ai_agent_team_memberships ai_agent_team_memberships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_agent_team_memberships
    ADD CONSTRAINT ai_agent_team_memberships_pkey PRIMARY KEY (id);


--
-- Name: ai_agents ai_agents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_agents
    ADD CONSTRAINT ai_agents_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: attendee_contacts attendee_contacts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendee_contacts
    ADD CONSTRAINT attendee_contacts_pkey PRIMARY KEY (id);


--
-- Name: board_columns board_columns_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.board_columns
    ADD CONSTRAINT board_columns_pkey PRIMARY KEY (id);


--
-- Name: calendar_events calendar_events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.calendar_events
    ADD CONSTRAINT calendar_events_pkey PRIMARY KEY (id);


--
-- Name: chat_contexts chat_contexts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_contexts
    ADD CONSTRAINT chat_contexts_pkey PRIMARY KEY (id);


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
-- Name: connector_accounts connector_accounts_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.connector_accounts
    ADD CONSTRAINT connector_accounts_pkey PRIMARY KEY (id);


--
-- Name: connector_event_mappings connector_event_mappings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.connector_event_mappings
    ADD CONSTRAINT connector_event_mappings_pkey PRIMARY KEY (id);


--
-- Name: connector_settings connector_settings_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.connector_settings
    ADD CONSTRAINT connector_settings_pkey PRIMARY KEY (id);


--
-- Name: connector_sync_logs connector_sync_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.connector_sync_logs
    ADD CONSTRAINT connector_sync_logs_pkey PRIMARY KEY (id);


--
-- Name: connector_webhook_subscriptions connector_webhook_subscriptions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.connector_webhook_subscriptions
    ADD CONSTRAINT connector_webhook_subscriptions_pkey PRIMARY KEY (id);


--
-- Name: currents currents_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.currents
    ADD CONSTRAINT currents_pkey PRIMARY KEY (id);


--
-- Name: events events_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT events_pkey PRIMARY KEY (id);


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
-- Name: message_feedbacks message_feedbacks_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message_feedbacks
    ADD CONSTRAINT message_feedbacks_pkey PRIMARY KEY (id);


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
-- Name: moderation_logs moderation_logs_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.moderation_logs
    ADD CONSTRAINT moderation_logs_pkey PRIMARY KEY (id);


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
-- Name: planning_relationships planning_relationships_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.planning_relationships
    ADD CONSTRAINT planning_relationships_pkey PRIMARY KEY (id);


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
-- Name: idx_on_chat_context_id_relationship_type_0ce2ed37ab; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_chat_context_id_relationship_type_0ce2ed37ab ON public.planning_relationships USING btree (chat_context_id, relationship_type);


--
-- Name: idx_on_connector_account_id_external_id_external_ty_53f2784fcd; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_connector_account_id_external_id_external_ty_53f2784fcd ON public.connector_event_mappings USING btree (connector_account_id, external_id, external_type);


--
-- Name: idx_on_connector_account_id_status_517af4a019; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_connector_account_id_status_517af4a019 ON public.connector_webhook_subscriptions USING btree (connector_account_id, status);


--
-- Name: idx_on_organization_id_enrichment_status_172943d07b; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX idx_on_organization_id_enrichment_status_172943d07b ON public.attendee_contacts USING btree (organization_id, enrichment_status);


--
-- Name: idx_on_user_id_provider_provider_uid_1cce2a45f8; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX idx_on_user_id_provider_provider_uid_1cce2a45f8 ON public.connector_accounts USING btree (user_id, provider, provider_uid);


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
-- Name: index_ai_agent_feedbacks_on_ai_agent_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_agent_feedbacks_on_ai_agent_id ON public.ai_agent_feedbacks USING btree (ai_agent_id);


--
-- Name: index_ai_agent_feedbacks_on_ai_agent_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_agent_feedbacks_on_ai_agent_run_id ON public.ai_agent_feedbacks USING btree (ai_agent_run_id);


--
-- Name: index_ai_agent_feedbacks_on_ai_agent_run_id_and_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_ai_agent_feedbacks_on_ai_agent_run_id_and_user_id ON public.ai_agent_feedbacks USING btree (ai_agent_run_id, user_id);


--
-- Name: index_ai_agent_feedbacks_on_rating; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_agent_feedbacks_on_rating ON public.ai_agent_feedbacks USING btree (rating);


--
-- Name: index_ai_agent_feedbacks_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_agent_feedbacks_on_user_id ON public.ai_agent_feedbacks USING btree (user_id);


--
-- Name: index_ai_agent_feedbacks_on_user_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_agent_feedbacks_on_user_id_and_created_at ON public.ai_agent_feedbacks USING btree (user_id, created_at);


--
-- Name: index_ai_agent_resources_on_ai_agent_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_agent_resources_on_ai_agent_id ON public.ai_agent_resources USING btree (ai_agent_id);


--
-- Name: index_ai_agent_resources_on_enabled; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_agent_resources_on_enabled ON public.ai_agent_resources USING btree (enabled);


--
-- Name: index_ai_agent_resources_on_resource_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_agent_resources_on_resource_type ON public.ai_agent_resources USING btree (resource_type);


--
-- Name: index_ai_agent_run_steps_on_ai_agent_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_agent_run_steps_on_ai_agent_run_id ON public.ai_agent_run_steps USING btree (ai_agent_run_id);


--
-- Name: index_ai_agent_run_steps_on_ai_agent_run_id_and_step_number; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_ai_agent_run_steps_on_ai_agent_run_id_and_step_number ON public.ai_agent_run_steps USING btree (ai_agent_run_id, step_number);


--
-- Name: index_ai_agent_run_steps_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_agent_run_steps_on_status ON public.ai_agent_run_steps USING btree (status);


--
-- Name: index_ai_agent_run_steps_on_step_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_agent_run_steps_on_step_type ON public.ai_agent_run_steps USING btree (step_type);


--
-- Name: index_ai_agent_runs_on_ai_agent_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_agent_runs_on_ai_agent_id ON public.ai_agent_runs USING btree (ai_agent_id);


--
-- Name: index_ai_agent_runs_on_completed_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_agent_runs_on_completed_at ON public.ai_agent_runs USING btree (completed_at);


--
-- Name: index_ai_agent_runs_on_invocable_type_and_invocable_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_agent_runs_on_invocable_type_and_invocable_id ON public.ai_agent_runs USING btree (invocable_type, invocable_id);


--
-- Name: index_ai_agent_runs_on_last_activity_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_agent_runs_on_last_activity_at ON public.ai_agent_runs USING btree (last_activity_at);


--
-- Name: index_ai_agent_runs_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_agent_runs_on_organization_id ON public.ai_agent_runs USING btree (organization_id);


--
-- Name: index_ai_agent_runs_on_parent_run_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_agent_runs_on_parent_run_id ON public.ai_agent_runs USING btree (parent_run_id);


--
-- Name: index_ai_agent_runs_on_started_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_agent_runs_on_started_at ON public.ai_agent_runs USING btree (started_at);


--
-- Name: index_ai_agent_runs_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_agent_runs_on_status ON public.ai_agent_runs USING btree (status);


--
-- Name: index_ai_agent_runs_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_agent_runs_on_user_id ON public.ai_agent_runs USING btree (user_id);


--
-- Name: index_ai_agent_team_memberships_on_ai_agent_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_agent_team_memberships_on_ai_agent_id ON public.ai_agent_team_memberships USING btree (ai_agent_id);


--
-- Name: index_ai_agent_team_memberships_on_ai_agent_id_and_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_ai_agent_team_memberships_on_ai_agent_id_and_team_id ON public.ai_agent_team_memberships USING btree (ai_agent_id, team_id);


--
-- Name: index_ai_agent_team_memberships_on_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_agent_team_memberships_on_team_id ON public.ai_agent_team_memberships USING btree (team_id);


--
-- Name: index_ai_agents_on_discarded_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_agents_on_discarded_at ON public.ai_agents USING btree (discarded_at);


--
-- Name: index_ai_agents_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_agents_on_organization_id ON public.ai_agents USING btree (organization_id);


--
-- Name: index_ai_agents_on_organization_id_and_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_ai_agents_on_organization_id_and_slug ON public.ai_agents USING btree (organization_id, slug);


--
-- Name: index_ai_agents_on_run_count; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_agents_on_run_count ON public.ai_agents USING btree (run_count);


--
-- Name: index_ai_agents_on_scope; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_agents_on_scope ON public.ai_agents USING btree (scope);


--
-- Name: index_ai_agents_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_agents_on_status ON public.ai_agents USING btree (status);


--
-- Name: index_ai_agents_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_ai_agents_on_user_id ON public.ai_agents USING btree (user_id);


--
-- Name: index_ai_agents_on_user_id_and_slug; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_ai_agents_on_user_id_and_slug ON public.ai_agents USING btree (user_id, slug);


--
-- Name: index_attendee_contacts_on_enriched_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_attendee_contacts_on_enriched_at ON public.attendee_contacts USING btree (enriched_at);


--
-- Name: index_attendee_contacts_on_enrichment_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_attendee_contacts_on_enrichment_status ON public.attendee_contacts USING btree (enrichment_status);


--
-- Name: index_attendee_contacts_on_organization_id_and_email; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_attendee_contacts_on_organization_id_and_email ON public.attendee_contacts USING btree (organization_id, email);


--
-- Name: index_board_columns_on_list_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_board_columns_on_list_id ON public.board_columns USING btree (list_id);


--
-- Name: index_calendar_events_on_attendees; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_calendar_events_on_attendees ON public.calendar_events USING gin (attendees);


--
-- Name: index_calendar_events_on_connector_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_calendar_events_on_connector_account_id ON public.calendar_events USING btree (connector_account_id);


--
-- Name: index_calendar_events_on_external_event_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_calendar_events_on_external_event_id ON public.calendar_events USING btree (external_event_id);


--
-- Name: index_calendar_events_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_calendar_events_on_organization_id ON public.calendar_events USING btree (organization_id);


--
-- Name: index_calendar_events_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_calendar_events_on_user_id ON public.calendar_events USING btree (user_id);


--
-- Name: index_calendar_events_on_user_id_and_start_time; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_calendar_events_on_user_id_and_start_time ON public.calendar_events USING btree (user_id, start_time);


--
-- Name: index_chat_contexts_on_chat_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_chat_contexts_on_chat_id ON public.chat_contexts USING btree (chat_id);


--
-- Name: index_chat_contexts_on_last_activity_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_chat_contexts_on_last_activity_at ON public.chat_contexts USING btree (last_activity_at);


--
-- Name: index_chat_contexts_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_chat_contexts_on_organization_id ON public.chat_contexts USING btree (organization_id);


--
-- Name: index_chat_contexts_on_post_creation_mode; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_chat_contexts_on_post_creation_mode ON public.chat_contexts USING btree (post_creation_mode);


--
-- Name: index_chat_contexts_on_state; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_chat_contexts_on_state ON public.chat_contexts USING btree (state);


--
-- Name: index_chat_contexts_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_chat_contexts_on_status ON public.chat_contexts USING btree (status);


--
-- Name: index_chat_contexts_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_chat_contexts_on_user_id ON public.chat_contexts USING btree (user_id);


--
-- Name: index_chats_on_chat_context_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_chats_on_chat_context_id ON public.chats USING btree (chat_context_id);


--
-- Name: index_chats_on_conversation_state; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_chats_on_conversation_state ON public.chats USING btree (conversation_state);


--
-- Name: index_chats_on_focused_resource_type_and_focused_resource_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_chats_on_focused_resource_type_and_focused_resource_id ON public.chats USING btree (focused_resource_type, focused_resource_id);


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
-- Name: index_chats_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_chats_on_organization_id ON public.chats USING btree (organization_id);


--
-- Name: index_chats_on_organization_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_chats_on_organization_id_and_created_at ON public.chats USING btree (organization_id, created_at);


--
-- Name: index_chats_on_organization_id_and_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_chats_on_organization_id_and_user_id ON public.chats USING btree (organization_id, user_id);


--
-- Name: index_chats_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_chats_on_status ON public.chats USING btree (status);


--
-- Name: index_chats_on_team_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_chats_on_team_id ON public.chats USING btree (team_id);


--
-- Name: index_chats_on_team_id_and_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_chats_on_team_id_and_user_id ON public.chats USING btree (team_id, user_id);


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
-- Name: index_chats_on_visibility; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_chats_on_visibility ON public.chats USING btree (visibility);


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
-- Name: index_comments_on_search_document; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_comments_on_search_document ON public.comments USING gin (search_document);


--
-- Name: index_comments_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_comments_on_user_id ON public.comments USING btree (user_id);


--
-- Name: index_connector_accounts_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_connector_accounts_on_created_at ON public.connector_accounts USING btree (created_at);


--
-- Name: index_connector_accounts_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_connector_accounts_on_organization_id ON public.connector_accounts USING btree (organization_id);


--
-- Name: index_connector_accounts_on_provider; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_connector_accounts_on_provider ON public.connector_accounts USING btree (provider);


--
-- Name: index_connector_accounts_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_connector_accounts_on_status ON public.connector_accounts USING btree (status);


--
-- Name: index_connector_accounts_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_connector_accounts_on_user_id ON public.connector_accounts USING btree (user_id);


--
-- Name: index_connector_event_mappings_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_connector_event_mappings_on_created_at ON public.connector_event_mappings USING btree (created_at);


--
-- Name: index_connector_event_mappings_on_local_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_connector_event_mappings_on_local_id ON public.connector_event_mappings USING btree (local_id);


--
-- Name: index_connector_event_mappings_on_local_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_connector_event_mappings_on_local_type ON public.connector_event_mappings USING btree (local_type);


--
-- Name: index_connector_settings_on_connector_account_id_and_key; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_connector_settings_on_connector_account_id_and_key ON public.connector_settings USING btree (connector_account_id, key);


--
-- Name: index_connector_sync_logs_on_connector_account_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_connector_sync_logs_on_connector_account_id ON public.connector_sync_logs USING btree (connector_account_id);


--
-- Name: index_connector_sync_logs_on_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_connector_sync_logs_on_created_at ON public.connector_sync_logs USING btree (created_at);


--
-- Name: index_connector_sync_logs_on_operation; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_connector_sync_logs_on_operation ON public.connector_sync_logs USING btree (operation);


--
-- Name: index_connector_sync_logs_on_status; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_connector_sync_logs_on_status ON public.connector_sync_logs USING btree (status);


--
-- Name: index_connector_webhook_subscriptions_on_expires_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_connector_webhook_subscriptions_on_expires_at ON public.connector_webhook_subscriptions USING btree (expires_at);


--
-- Name: index_connector_webhook_subscriptions_on_subscription_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_connector_webhook_subscriptions_on_subscription_id ON public.connector_webhook_subscriptions USING btree (subscription_id);


--
-- Name: index_events_on_actor_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_events_on_actor_id ON public.events USING btree (actor_id);


--
-- Name: index_events_on_actor_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_events_on_actor_id_and_created_at ON public.events USING btree (actor_id, created_at);


--
-- Name: index_events_on_event_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_events_on_event_type ON public.events USING btree (event_type);


--
-- Name: index_events_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_events_on_organization_id ON public.events USING btree (organization_id);


--
-- Name: index_events_on_organization_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_events_on_organization_id_and_created_at ON public.events USING btree (organization_id, created_at);


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
-- Name: index_list_items_on_search_document; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_list_items_on_search_document ON public.list_items USING gin (search_document);


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
-- Name: index_lists_on_search_document; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_lists_on_search_document ON public.lists USING gin (search_document);


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
-- Name: index_message_feedbacks_on_chat_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_message_feedbacks_on_chat_id ON public.message_feedbacks USING btree (chat_id);


--
-- Name: index_message_feedbacks_on_message_id_and_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_message_feedbacks_on_message_id_and_user_id ON public.message_feedbacks USING btree (message_id, user_id);


--
-- Name: index_message_feedbacks_on_rating; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_message_feedbacks_on_rating ON public.message_feedbacks USING btree (rating);


--
-- Name: index_message_feedbacks_on_user_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_message_feedbacks_on_user_id_and_created_at ON public.message_feedbacks USING btree (user_id, created_at);


--
-- Name: index_messages_on_blocked; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_messages_on_blocked ON public.messages USING btree (blocked);


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
-- Name: index_messages_on_llm_provider; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_messages_on_llm_provider ON public.messages USING btree (llm_provider);


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
-- Name: index_messages_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_messages_on_organization_id ON public.messages USING btree (organization_id);


--
-- Name: index_messages_on_organization_id_and_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_messages_on_organization_id_and_user_id ON public.messages USING btree (organization_id, user_id);


--
-- Name: index_messages_on_role; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_messages_on_role ON public.messages USING btree (role);


--
-- Name: index_messages_on_template_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_messages_on_template_type ON public.messages USING btree (template_type);


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
-- Name: index_moderation_logs_on_action_taken; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_moderation_logs_on_action_taken ON public.moderation_logs USING btree (action_taken);


--
-- Name: index_moderation_logs_on_chat_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_moderation_logs_on_chat_id ON public.moderation_logs USING btree (chat_id);


--
-- Name: index_moderation_logs_on_message_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_moderation_logs_on_message_id ON public.moderation_logs USING btree (message_id);


--
-- Name: index_moderation_logs_on_organization_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_moderation_logs_on_organization_id ON public.moderation_logs USING btree (organization_id);


--
-- Name: index_moderation_logs_on_organization_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_moderation_logs_on_organization_id_and_created_at ON public.moderation_logs USING btree (organization_id, created_at);


--
-- Name: index_moderation_logs_on_user_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_moderation_logs_on_user_id ON public.moderation_logs USING btree (user_id);


--
-- Name: index_moderation_logs_on_user_id_and_created_at; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_moderation_logs_on_user_id_and_created_at ON public.moderation_logs USING btree (user_id, created_at);


--
-- Name: index_moderation_logs_on_violation_type; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_moderation_logs_on_violation_type ON public.moderation_logs USING btree (violation_type);


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
-- Name: index_planning_relationships_on_chat_context_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_planning_relationships_on_chat_context_id ON public.planning_relationships USING btree (chat_context_id);


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
-- Name: index_tags_on_search_document; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tags_on_search_document ON public.tags USING gin (search_document);


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
-- Name: ai_agent_runs fk_rails_0d9588fc2e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_agent_runs
    ADD CONSTRAINT fk_rails_0d9588fc2e FOREIGN KEY (ai_agent_id) REFERENCES public.ai_agents(id);


--
-- Name: moderation_logs fk_rails_0f166e8887; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.moderation_logs
    ADD CONSTRAINT fk_rails_0f166e8887 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


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
-- Name: calendar_events fk_rails_15e1fec6ce; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.calendar_events
    ADD CONSTRAINT fk_rails_15e1fec6ce FOREIGN KEY (connector_account_id) REFERENCES public.connector_accounts(id);


--
-- Name: events fk_rails_163b5130b5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT fk_rails_163b5130b5 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: chats fk_rails_1835d93df1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chats
    ADD CONSTRAINT fk_rails_1835d93df1 FOREIGN KEY (model_id) REFERENCES public.models(id);


--
-- Name: ai_agents fk_rails_1b5d51740c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_agents
    ADD CONSTRAINT fk_rails_1b5d51740c FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: ai_agents fk_rails_1fa8066c07; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_agents
    ADD CONSTRAINT fk_rails_1fa8066c07 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: messages fk_rails_273a25a7a6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT fk_rails_273a25a7a6 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: events fk_rails_2c515e778f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.events
    ADD CONSTRAINT fk_rails_2c515e778f FOREIGN KEY (actor_id) REFERENCES public.users(id);


--
-- Name: chat_contexts fk_rails_3560951342; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_contexts
    ADD CONSTRAINT fk_rails_3560951342 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: connector_sync_logs fk_rails_35b6930281; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.connector_sync_logs
    ADD CONSTRAINT fk_rails_35b6930281 FOREIGN KEY (connector_account_id) REFERENCES public.connector_accounts(id);


--
-- Name: collaborators fk_rails_3d4aaacbb1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.collaborators
    ADD CONSTRAINT fk_rails_3d4aaacbb1 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: messages fk_rails_41c70a97c6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT fk_rails_41c70a97c6 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: ai_agent_team_memberships fk_rails_4b41739a47; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_agent_team_memberships
    ADD CONSTRAINT fk_rails_4b41739a47 FOREIGN KEY (team_id) REFERENCES public.teams(id);


--
-- Name: recovery_contexts fk_rails_51e01bf1ba; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recovery_contexts
    ADD CONSTRAINT fk_rails_51e01bf1ba FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: moderation_logs fk_rails_5212b548a1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.moderation_logs
    ADD CONSTRAINT fk_rails_5212b548a1 FOREIGN KEY (chat_id) REFERENCES public.chats(id);


--
-- Name: message_feedbacks fk_rails_54dd88c416; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message_feedbacks
    ADD CONSTRAINT fk_rails_54dd88c416 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: messages fk_rails_552873cb52; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.messages
    ADD CONSTRAINT fk_rails_552873cb52 FOREIGN KEY (tool_call_id) REFERENCES public.tool_calls(id);


--
-- Name: organization_memberships fk_rails_57cf70d280; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.organization_memberships
    ADD CONSTRAINT fk_rails_57cf70d280 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: message_feedbacks fk_rails_588822f63b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message_feedbacks
    ADD CONSTRAINT fk_rails_588822f63b FOREIGN KEY (chat_id) REFERENCES public.chats(id);


--
-- Name: team_memberships fk_rails_5aba9331a7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.team_memberships
    ADD CONSTRAINT fk_rails_5aba9331a7 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: moderation_logs fk_rails_61576f3f6e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.moderation_logs
    ADD CONSTRAINT fk_rails_61576f3f6e FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: ai_agent_feedbacks fk_rails_61a9fca31d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_agent_feedbacks
    ADD CONSTRAINT fk_rails_61a9fca31d FOREIGN KEY (ai_agent_run_id) REFERENCES public.ai_agent_runs(id);


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
-- Name: ai_agent_run_steps fk_rails_6a2d3d54b8; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_agent_run_steps
    ADD CONSTRAINT fk_rails_6a2d3d54b8 FOREIGN KEY (ai_agent_run_id) REFERENCES public.ai_agent_runs(id);


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
-- Name: connector_webhook_subscriptions fk_rails_7e61d1ae5e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.connector_webhook_subscriptions
    ADD CONSTRAINT fk_rails_7e61d1ae5e FOREIGN KEY (connector_account_id) REFERENCES public.connector_accounts(id);


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
-- Name: chats fk_rails_81b9fd7c23; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chats
    ADD CONSTRAINT fk_rails_81b9fd7c23 FOREIGN KEY (team_id) REFERENCES public.teams(id);


--
-- Name: message_feedbacks fk_rails_84df82fe83; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.message_feedbacks
    ADD CONSTRAINT fk_rails_84df82fe83 FOREIGN KEY (message_id) REFERENCES public.messages(id);


--
-- Name: connector_accounts fk_rails_909e7c6acc; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.connector_accounts
    ADD CONSTRAINT fk_rails_909e7c6acc FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: calendar_events fk_rails_90c7e652b9; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.calendar_events
    ADD CONSTRAINT fk_rails_90c7e652b9 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: calendar_events fk_rails_930e3c0bf4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.calendar_events
    ADD CONSTRAINT fk_rails_930e3c0bf4 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: ai_agent_resources fk_rails_98ab80f011; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_agent_resources
    ADD CONSTRAINT fk_rails_98ab80f011 FOREIGN KEY (ai_agent_id) REFERENCES public.ai_agents(id);


--
-- Name: active_storage_variant_records fk_rails_993965df05; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_variant_records
    ADD CONSTRAINT fk_rails_993965df05 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: connector_event_mappings fk_rails_9c2eb634de; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.connector_event_mappings
    ADD CONSTRAINT fk_rails_9c2eb634de FOREIGN KEY (connector_account_id) REFERENCES public.connector_accounts(id);


--
-- Name: tool_calls fk_rails_9c8daee481; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tool_calls
    ADD CONSTRAINT fk_rails_9c8daee481 FOREIGN KEY (message_id) REFERENCES public.messages(id);


--
-- Name: connector_accounts fk_rails_9f398701e5; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.connector_accounts
    ADD CONSTRAINT fk_rails_9f398701e5 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: taggings fk_rails_9fcd2e236b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.taggings
    ADD CONSTRAINT fk_rails_9fcd2e236b FOREIGN KEY (tag_id) REFERENCES public.tags(id);


--
-- Name: attendee_contacts fk_rails_9fd5ba6572; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendee_contacts
    ADD CONSTRAINT fk_rails_9fd5ba6572 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: teams fk_rails_a068b3a692; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.teams
    ADD CONSTRAINT fk_rails_a068b3a692 FOREIGN KEY (created_by_id) REFERENCES public.users(id);


--
-- Name: attendee_contacts fk_rails_b1199659c3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.attendee_contacts
    ADD CONSTRAINT fk_rails_b1199659c3 FOREIGN KEY (user_id) REFERENCES public.users(id) ON DELETE SET NULL;


--
-- Name: ai_agent_feedbacks fk_rails_b8e5ae114f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_agent_feedbacks
    ADD CONSTRAINT fk_rails_b8e5ae114f FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: chat_contexts fk_rails_bc0ea8d29b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_contexts
    ADD CONSTRAINT fk_rails_bc0ea8d29b FOREIGN KEY (chat_id) REFERENCES public.chats(id);


--
-- Name: ai_agent_feedbacks fk_rails_bd44f18125; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_agent_feedbacks
    ADD CONSTRAINT fk_rails_bd44f18125 FOREIGN KEY (ai_agent_id) REFERENCES public.ai_agents(id);


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
-- Name: ai_agent_runs fk_rails_c29504744a; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_agent_runs
    ADD CONSTRAINT fk_rails_c29504744a FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: active_storage_attachments fk_rails_c3b3935057; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.active_storage_attachments
    ADD CONSTRAINT fk_rails_c3b3935057 FOREIGN KEY (blob_id) REFERENCES public.active_storage_blobs(id);


--
-- Name: planning_relationships fk_rails_d50b603b78; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.planning_relationships
    ADD CONSTRAINT fk_rails_d50b603b78 FOREIGN KEY (chat_context_id) REFERENCES public.chat_contexts(id);


--
-- Name: users fk_rails_d5e043db78; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.users
    ADD CONSTRAINT fk_rails_d5e043db78 FOREIGN KEY (suspended_by_id) REFERENCES public.users(id);


--
-- Name: chats fk_rails_d5fb07dc4c; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chats
    ADD CONSTRAINT fk_rails_d5fb07dc4c FOREIGN KEY (chat_context_id) REFERENCES public.chat_contexts(id);


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
-- Name: ai_agent_runs fk_rails_dd6e51e8ac; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_agent_runs
    ADD CONSTRAINT fk_rails_dd6e51e8ac FOREIGN KEY (parent_run_id) REFERENCES public.ai_agent_runs(id);


--
-- Name: chat_contexts fk_rails_de81198315; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chat_contexts
    ADD CONSTRAINT fk_rails_de81198315 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: ai_agent_runs fk_rails_e0a7859fc6; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_agent_runs
    ADD CONSTRAINT fk_rails_e0a7859fc6 FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: chats fk_rails_e555f43151; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chats
    ADD CONSTRAINT fk_rails_e555f43151 FOREIGN KEY (user_id) REFERENCES public.users(id);


--
-- Name: ai_agent_team_memberships fk_rails_e7c38eac12; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ai_agent_team_memberships
    ADD CONSTRAINT fk_rails_e7c38eac12 FOREIGN KEY (ai_agent_id) REFERENCES public.ai_agents(id);


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
-- Name: moderation_logs fk_rails_f309c5a816; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.moderation_logs
    ADD CONSTRAINT fk_rails_f309c5a816 FOREIGN KEY (message_id) REFERENCES public.messages(id);


--
-- Name: recovery_contexts fk_rails_f37be66aa7; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.recovery_contexts
    ADD CONSTRAINT fk_rails_f37be66aa7 FOREIGN KEY (chat_id) REFERENCES public.chats(id);


--
-- Name: chats fk_rails_f5e99d4d5f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.chats
    ADD CONSTRAINT fk_rails_f5e99d4d5f FOREIGN KEY (organization_id) REFERENCES public.organizations(id);


--
-- Name: connector_settings fk_rails_f8a296dae1; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.connector_settings
    ADD CONSTRAINT fk_rails_f8a296dae1 FOREIGN KEY (connector_account_id) REFERENCES public.connector_accounts(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20260325000007'),
('20260325000006'),
('20260325000005'),
('20260325000004'),
('20260325000003'),
('20260325000002'),
('20260325000001'),
('20260323000001'),
('20260322000003'),
('20260322000002'),
('20260322000001'),
('20260320000003'),
('20260320000002'),
('20260320000001'),
('20260320000000'),
('20260319230043'),
('20260319000003'),
('20260319000002'),
('20260319000001'),
('20260319000000'),
('20260318020551'),
('20260309225939'),
('20251208195450'),
('20251208185450'),
('20251208185230'),
('20251208182655'),
('20251208120001'),
('20251208120000'),
('20251208050101'),
('20251208050100'),
('20251208050000'),
('20251208043416'),
('20251208043414'),
('20251208043412'),
('20251208043410'),
('20251208043409'),
('20251208043408'),
('20251208043407'),
('20251208043406'),
('20251206170353'),
('20251115200022'),
('20251115200021'),
('20251115200020'),
('20251115200019'),
('20251011000104'),
('20251010235748'),
('20251010235747'),
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
('20250624223654'),
('20250624223653'),
('20250623211535'),
('20250623211119'),
('20250623211117'),
('20250623100332'),
('20250623083443'),
('20250623083440');

