# config/initializers/conversation_health.rb

# Require the middleware class explicitly since it's not autoloaded during initialization
require Rails.root.join("app", "middleware", "conversation_error_middleware")

Rails.application.configure do
  # Conversation health monitoring configuration
  config.conversation_health = ActiveSupport::OrderedOptions.new

  # Enable/disable health monitoring
  config.conversation_health.enabled = ENV.fetch("CONVERSATION_HEALTH_ENABLED", "true") == "true"

  # How often to run health checks (in minutes)
  config.conversation_health.check_interval = ENV.fetch("CONVERSATION_HEALTH_INTERVAL", "60").to_i

  # Health threshold for alerts (percentage)
  config.conversation_health.alert_threshold = ENV.fetch("CONVERSATION_HEALTH_THRESHOLD", "95").to_f

  # Maximum age for chats before archiving if broken (in days)
  config.conversation_health.max_broken_chat_age = ENV.fetch("MAX_BROKEN_CHAT_AGE", "7").to_i

  # Whether to auto-archive severely broken chats
  config.conversation_health.auto_archive_broken = ENV.fetch("AUTO_ARCHIVE_BROKEN_CHATS", "true") == "true"

  # Add middleware BEFORE the stack is frozen (not in after_initialize)
  if Rails.env.production? || ENV["CONVERSATION_ERROR_MIDDLEWARE"] == "true"
    config.middleware.use ConversationErrorMiddleware
  end
end

# Schedule regular health checks if monitoring is enabled
Rails.application.config.after_initialize do
  if Rails.application.config.conversation_health.enabled && defined?(Sidekiq::Cron)
    # Schedule health check every hour
    Sidekiq::Cron::Job.create(
      name: "Conversation Health Check",
      class: "ConversationHealthCheckJob",
      cron: "0 * * * *" # Every hour
    )
  end
end
