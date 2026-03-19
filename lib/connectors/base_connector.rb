module Connectors
  # Abstract base class for all connectors
  # Subclasses should define metadata using class methods
  # All instances require a valid authenticated user context
  class BaseConnector
    attr_reader :account

    def initialize(account)
      raise "User must be authenticated" unless Current.user.present?
      raise "User does not own this connector account" unless account.user_id == Current.user.id

      @account = account
    end

    class << self
      attr_accessor :_key, :_name, :_category, :_icon, :_description, :_requires_oauth, :_oauth_scopes, :_settings_schema

      def connector_key(key)
        @_key = key
      end

      def connector_name(name)
        @_name = name
      end

      def connector_category(category)
        @_category = category
      end

      def connector_icon(icon)
        @_icon = icon
      end

      def connector_description(description)
        @_description = description
      end

      def requires_oauth(value = true)
        @_requires_oauth = value
      end

      def oauth_scopes(scopes)
        @_oauth_scopes = scopes
      end

      def settings_schema(schema)
        @_settings_schema = schema
      end

      # Getter methods for metadata
      def key
        @_key || raise("Connector #{self} must define connector_key")
      end

      def name
        @_name || raise("Connector #{self} must define connector_name")
      end

      def category
        @_category || raise("Connector #{self} must define connector_category")
      end

      def icon
        @_icon || "link"
      end

      def description
        @_description || ""
      end

      def oauth_required?
        @_requires_oauth != false
      end

      def oauth_scopes_list
        @_oauth_scopes || []
      end

      def schema
        @_settings_schema || {}
      end
    end

    # Instance methods - these should be overridden by subclasses

    def connected?
      account.connected?
    end

    def token_expired?
      account.token_expired?
    end

    # Abstract methods - must be implemented by subclasses
    def pull
      raise NotImplementedError, "Subclasses must implement #pull"
    end

    def push(data)
      raise NotImplementedError, "Subclasses must implement #push(data)"
    end

    def test_connection
      raise NotImplementedError, "Subclasses must implement #test_connection"
    end
  end
end
