# config/initializers/ruby_llm.rb

# Main RubyLLM configuration
# Note: use_new_acts_as is set in config/application.rb to ensure it loads before models

require "ruby_llm"

RubyLLM.configure do |config|
  # API Keys - will come from .env in dev/test, from server environment in production
  config.openai_api_key = ENV["OPENAI_API_KEY"]
  config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"] if ENV["ANTHROPIC_API_KEY"]

  # Default model configuration - use the correct OpenAI model name
  config.default_model = ENV.fetch("LLM_MODEL", "gpt-4o-mini")

  # Default moderation model
  config.default_moderation_model = ENV.fetch("OPENAI_MODERATION_MODEL", "omni-moderation-latest")
end

# Log configuration status
if defined?(RubyLLM)
  Rails.logger.info "✅ RubyLLM configured with provider: #{ENV.fetch('LLM_PROVIDER', 'openai')}"
  Rails.logger.info "✅ RubyLLM default model: #{ENV.fetch('LLM_MODEL', 'gpt-4o-mini')}"

  # Warn if API keys are missing
  if ENV["OPENAI_API_KEY"].blank? && ENV["ANTHROPIC_API_KEY"].blank?
    Rails.logger.warn "⚠️  No API keys configured for RubyLLM (OPENAI_API_KEY or ANTHROPIC_API_KEY)"
  end

  # Debug logging in development
  if Rails.env.development? && ENV["OPENAI_API_KEY"].present?
    Rails.logger.info "✅ OPENAI_API_KEY configured (first 10 chars): #{ENV['OPENAI_API_KEY'].slice(0, 10)}..."
  end
end
