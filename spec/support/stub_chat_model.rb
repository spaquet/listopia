# spec/support/stub_chat_model.rb
# Minimal RubyLLM mock for tests

if Rails.env.test?
  # Mock RubyLLM to prevent "Unknown model" errors
  module RubyLLM
    def self.models
      @mocked_models ||= MockModels.new
    end

    class MockModels
      def resolve(model_id, provider: nil)
        [ {}, provider || 'mock' ]
      end
    end
  end unless defined?(RubyLLM)
end
