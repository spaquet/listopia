# config/initializers/mcp.rb
Rails.application.configure do
  # MCP Configuration
  config.mcp = ActiveSupport::OrderedOptions.new

  # LLM Provider settings
  config.mcp.provider = ENV.fetch("LLM_PROVIDER", "openai")
  config.mcp.api_key = case config.mcp.provider
  when "openai"
    ENV["OPENAI_API_KEY"]
  when "anthropic"
    ENV["ANTHROPIC_API_KEY"]
  when "google"
    ENV["GOOGLE_API_KEY"]
  else
    nil
  end

  config.mcp.model = ENV.fetch("LLM_MODEL", "gpt-4-turbo-preview")

  # MCP Feature flags
  config.mcp.enabled = config.mcp.api_key.present?
  config.mcp.async_processing = ENV.fetch("MCP_ASYNC", "false") == "true"

  # Rate limiting
  config.mcp.rate_limit_per_hour = ENV.fetch("MCP_RATE_LIMIT", "100").to_i
  config.mcp.rate_limit_per_minute = ENV.fetch("MCP_RATE_LIMIT_MINUTE", "10").to_i

  # Logging
  config.mcp.log_level = ENV.fetch("MCP_LOG_LEVEL", "info").to_sym

  # Security
  config.mcp.max_message_length = ENV.fetch("MCP_MAX_MESSAGE_LENGTH", "2000").to_i
  config.mcp.max_context_size = ENV.fetch("MCP_MAX_CONTEXT_SIZE", "10000").to_i

  # Error Recovery Configuration (Phase 2 additions)
  config.mcp.error_recovery = ActiveSupport::OrderedOptions.new
  config.mcp.error_recovery.enabled = ENV.fetch("MCP_ERROR_RECOVERY_ENABLED", "true") == "true"
  config.mcp.error_recovery.circuit_breaker_threshold = ENV.fetch("MCP_CIRCUIT_BREAKER_THRESHOLD", "5").to_i
  config.mcp.error_recovery.circuit_breaker_timeout = ENV.fetch("MCP_CIRCUIT_BREAKER_TIMEOUT", "60").to_i
  config.mcp.error_recovery.checkpoint_retention_days = ENV.fetch("MCP_CHECKPOINT_RETENTION_DAYS", "7").to_i
  config.mcp.error_recovery.max_recovery_attempts = ENV.fetch("MCP_MAX_RECOVERY_ATTEMPTS", "3").to_i

  # State Management Configuration
  config.mcp.state_management = ActiveSupport::OrderedOptions.new
  config.mcp.state_management.auto_checkpoint = ENV.fetch("MCP_AUTO_CHECKPOINT", "true") == "true"
  config.mcp.state_management.aggressive_cleanup_threshold = ENV.fetch("MCP_AGGRESSIVE_CLEANUP_THRESHOLD", "20").to_i

  # Warn if MCP is disabled
  unless config.mcp.enabled
    Rails.logger.warn "MCP is disabled: Missing #{config.mcp.provider.upcase}_API_KEY environment variable"
  end
end
