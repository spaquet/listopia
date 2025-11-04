# config/initializers/ruby_llm.rb
# Main RubyLLM configuration

require "ruby_llm"

RubyLLM.configure do |config|
  # API Keys - from environment variables
  config.openai_api_key = ENV["OPENAI_API_KEY"]
  config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"] if ENV["ANTHROPIC_API_KEY"]

  # Default model configuration
  # Valid models: https://rubyllm.com/available-models/
  config.default_model = ENV.fetch("LLM_MODEL", "gpt-4o-mini")

  # Default moderation model
  config.default_moderation_model = ENV.fetch("OPENAI_MODERATION_MODEL", "omni-moderation-latest")

  # Log configuration status
  if Rails.env.test?
    Rails.logger.info "✅ RubyLLM configured for TEST environment"
  else
    Rails.logger.info "✅ RubyLLM configured for #{Rails.env.upcase}"
    Rails.logger.info "   Provider: #{ENV.fetch('LLM_PROVIDER', 'openai')}"
    Rails.logger.info "   Default model: #{ENV.fetch('LLM_MODEL', 'gpt-4o-mini')}"

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
