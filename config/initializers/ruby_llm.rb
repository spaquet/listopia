# config/initializers/ruby_llm.rb

# Main RubyLLM configuration
# Note: use_new_acts_as is set in config/application.rb to ensure it loads before models

require "ruby_llm"

RubyLLM.configure do |config|
  if Rails.env.test?
    # Test environment: disable model validation and use a mock model
    config.skip_model_validation = true if config.respond_to?(:skip_model_validation=)

    # Set a valid test model - use the cost-effective gpt-4o-mini model
    config.default_model = "gpt-4o-mini"

    # Disable API calls in test
    config.openai_api_key = "sk-test-key-do-not-use"

    Rails.logger.info "✅ RubyLLM configured for TEST environment"
    Rails.logger.info "   - Model validation: DISABLED"
    Rails.logger.info "   - Default model: gpt-4o-mini"
    Rails.logger.info "   - API calls: MOCKED"
  else
    # Production/Development environment: normal configuration

    # API Keys - will come from .env in dev/test, from server environment in production
    config.openai_api_key = ENV["OPENAI_API_KEY"]
    config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"] if ENV["ANTHROPIC_API_KEY"]

    # Default model configuration - use the correct OpenAI model name
    # Valid models from https://rubyllm.com/available-models/:
    # OpenAI: gpt-4.1, gpt-4.1-mini, gpt-4.1-nano, gpt-4o, gpt-4o-mini, gpt-3.5-turbo
    # Anthropic: claude-3-haiku-20240307, claude-3-5-haiku-20241022, claude-opus-4-20250514, etc.
    config.default_model = ENV.fetch("LLM_MODEL", "gpt-4o-mini")

    # Default moderation model
    config.default_moderation_model = ENV.fetch("OPENAI_MODERATION_MODEL", "omni-moderation-latest")

    Rails.logger.info "✅ RubyLLM configured for #{Rails.env.upcase}"
    Rails.logger.info "   Provider: #{ENV.fetch('LLM_PROVIDER', 'openai')}"
    Rails.logger.info "   Default model: #{ENV.fetch('LLM_MODEL', 'gpt-4o-mini')}"
    Rails.logger.info "   Moderation model: #{ENV.fetch('OPENAI_MODERATION_MODEL', 'omni-moderation-latest')}"

    # Warn if API keys are missing
    if ENV["OPENAI_API_KEY"].blank? && ENV["ANTHROPIC_API_KEY"].blank?
      Rails.logger.warn "⚠️  WARNING: No API keys configured for RubyLLM"
      Rails.logger.warn "   Set OPENAI_API_KEY or ANTHROPIC_API_KEY environment variables"
    end

    # Debug logging in development
    if Rails.env.development? && ENV["OPENAI_API_KEY"].present?
      Rails.logger.info "✅ OPENAI_API_KEY configured (first 10 chars): #{ENV['OPENAI_API_KEY'].slice(0, 10)}..."
    end
  end
end
