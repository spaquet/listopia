# spec/support/ruby_llm_stubs.rb
# Stub out RubyLLM functionality in tests to prevent model validation errors

if Rails.env.test?
  # Mock RubyLLM to prevent "Unknown model" errors
  module RubyLLM
    # Create a mock configuration that accepts any model name
    class MockConfig
      attr_accessor :default_model, :default_moderation_model, :openai_api_key,
                    :anthropic_api_key, :skip_model_validation, :use_new_acts_as

      def initialize
        @default_model = "gpt-4o-mini"
        @default_moderation_model = "omni-moderation-latest"
        @openai_api_key = "sk-test-key"
        @anthropic_api_key = nil
        @skip_model_validation = true
        @use_new_acts_as = true
      end

      def respond_to?(method_name, include_private = false)
        true
      end

      def method_missing(method_name, *args, &block)
        # Accept any method call without error
        nil
      end
    end

    # Mock the configure method
    def self.configure
      yield @config = MockConfig.new
      @config
    end

    # Return the mock config when accessed
    def self.config
      @config ||= MockConfig.new
    end
  end

  # Ensure the Chat model can be created without RubyLLM validation
  class Chat < ApplicationRecord
    # Skip the acts_as_chat initialization in tests
    def self.acts_as_chat_available?
      false
    end

    # Mock the acts_as_chat method to prevent errors
    def self.acts_as_chat(options = {})
      # Do nothing in tests - skip all RubyLLM initialization
      nil
    end
  end if defined?(Chat)

  Rails.logger.info "✅ RubyLLM test stubs loaded"
end
