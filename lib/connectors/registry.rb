module Connectors
  # Registry for discovering and accessing connectors
  class Registry
    @connectors = {}

    def self.register(connector_class)
      key = connector_class.key
      @connectors[key] = connector_class
    end

    def self.all
      @connectors.values
    end

    def self.find(key)
      @connectors[key]
    end

    def self.by_category(category)
      @connectors.values.select { |c| c.category == category }
    end

    def self.exists?(key)
      @connectors.key?(key)
    end
  end
end
