# spec/support/ruby_llm_stub.rb
# Complete stub of RubyLLM - prevents real API calls and model resolution in tests

module RubyLLM
  # Stub configuration
  class Configuration
    attr_accessor :openai_api_key, :anthropic_api_key, :default_model, :default_moderation_model

    def initialize
      @settings = {}
    end

    def method_missing(method_name, *args, &block)
      if method_name.to_s.end_with?('=')
        key = method_name.to_s[0..-2].to_sym
        @settings[key] = args.first
      else
        @settings[method_name] || nil
      end
    end

    def respond_to_missing?(method_name, include_private = false)
      true
    end
  end

  # Stub models registry
  class ModelsRegistry
    def all
      []
    end

    def resolve(model_id, provider: nil)
      model_info = {
        'id' => model_id,
        'name' => model_id,
        'provider' => provider || 'openai',
        'context_window' => 128000,
        'max_output_tokens' => 4096
      }
      [ model_info, provider || 'openai' ]
    end

    def refresh!
      # No-op
    end

    def method_missing(method_name, *args)
      []
    end

    def respond_to_missing?(method_name, include_private = false)
      true
    end
  end

  # Main RubyLLM interface
  class << self
    @@configuration = nil
    @@models = nil

    def configuration
      @@configuration ||= Configuration.new
    end

    def configure
      yield(configuration) if block_given?
    end

    def models
      @@models ||= ModelsRegistry.new
    end

    # Prevent undefined method errors
    def method_missing(method_name, *args)
      # Return stub config for any unknown method
      configuration
    end

    def respond_to_missing?(method_name, include_private = false)
      true
    end
  end
end

# Force reload Chat to use our stub
if defined?(Chat)
  Chat.instance_variable_set(:@llm_config, nil)
end
