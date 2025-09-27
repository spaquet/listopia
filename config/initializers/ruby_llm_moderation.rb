# config/initializers/ruby_llm_moderation.rb
# Simple RubyLLM moderation configuration
# LISTOPIA_USE_MODERATION defaults to 'true' - moderation is enabled by default

# Check if moderation should be enabled (defaults to true)
moderation_enabled = ENV.fetch("LISTOPIA_USE_MODERATION", "true").downcase == "true"

if defined?(RubyLLM) && moderation_enabled
  RubyLLM.configure do |config|
    # Set OpenAI API key for moderation
    config.openai_api_key = ENV["OPENAI_API_KEY"]

    # Set default moderation model (optional)
    config.default_moderation_model = ENV.fetch("OPENAI_MODERATION_MODEL", "omni-moderation-latest")
  end

  Rails.logger.info "🛡️  Listopia Content Moderation: ENABLED"

  # Warn if API key is missing
  if ENV["OPENAI_API_KEY"].blank?
    Rails.logger.error "❌ Content moderation enabled but OPENAI_API_KEY not configured!"
  end
else
  Rails.logger.info "🛡️  Listopia Content Moderation: DISABLED"
end
