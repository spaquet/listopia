# config/initializers/ruby_llm_moderation.rb

# Simple RubyLLM moderation configuration
# LISTOPIA_USE_MODERATION defaults to 'true' - moderation is enabled by default

# Main RubyLLM configuration has been moved to config/application.rb
# This file now only handles moderation-specific runtime checks

# Check if moderation should be enabled (defaults to true)
moderation_enabled = ENV.fetch("LISTOPIA_USE_MODERATION", "true").downcase == "true"

if defined?(RubyLLM) && moderation_enabled
  # Note: RubyLLM.configure has already been called in config/application.rb
  # We don't need to configure again here, just check and log the status

  Rails.logger.info "🛡️  Listopia Content Moderation: ENABLED"
  Rails.logger.info "🛡️  Moderation model: #{ENV.fetch('OPENAI_MODERATION_MODEL', 'omni-moderation-latest')}"

  # Warn if API key is missing
  if ENV["OPENAI_API_KEY"].blank?
    Rails.logger.error "❌ Content moderation enabled but OPENAI_API_KEY not configured!"
  end
else
  Rails.logger.info "🛡️  Listopia Content Moderation: DISABLED"
end
