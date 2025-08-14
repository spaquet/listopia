# config/initializers/ruby_llm.rb
require "ruby_llm"

RubyLLM.configure do |config|
  # Provider API Keys - Set only for providers you plan to use
  config.openai_api_key = ENV.fetch("OPENAI_API_KEY", nil)
  config.openai_organization_id = ENV.fetch("OPENAI_ORGANIZATION_ID", nil)
  config.openai_project_id = ENV.fetch("OPENAI_PROJECT_ID", nil)
  config.anthropic_api_key = ENV.fetch("ANTHROPIC_API_KEY", nil)
  config.gemini_api_key = ENV.fetch("GEMINI_API_KEY", nil)
  config.deepseek_api_key = ENV.fetch("DEEPSEEK_API_KEY", nil)
  config.openrouter_api_key = ENV.fetch("OPENROUTER_API_KEY", nil)
  config.ollama_api_base = ENV.fetch("OLLAMA_API_BASE", nil)

  # AWS Bedrock Credentials (if using Bedrock)
  config.bedrock_api_key = ENV.fetch("AWS_ACCESS_KEY_ID", nil)
  config.bedrock_secret_key = ENV.fetch("AWS_SECRET_ACCESS_KEY", nil)
  config.bedrock_region = ENV.fetch("AWS_REGION", nil)
  config.bedrock_session_token = ENV.fetch("AWS_SESSION_TOKEN", nil)

  # Custom OpenAI endpoint (for Azure OpenAI, proxies, etc.)
  config.openai_api_base = ENV.fetch("OPENAI_API_BASE", nil)

  # Default Models - Match your MCP configuration
  default_model = ENV.fetch("LLM_MODEL", "gpt-4-turbo-preview")
  config.default_model = default_model
  config.default_embedding_model = "text-embedding-3-small"
  config.default_image_model = "dall-e-3"

  # Connection Settings
  config.request_timeout = 120
  config.max_retries = 3
  config.retry_interval = 0.1
  config.retry_backoff_factor = 2
  config.retry_interval_randomness = 0.5

  # HTTP Proxy Support (if needed)
  config.http_proxy = ENV.fetch("HTTP_PROXY", nil)

  # Logging Settings
  config.log_file = Rails.root.join("log", "ruby_llm.log").to_s
  config.log_level = Rails.env.production? ? :info : :debug

  # Use Rails logger in Rails environment
  config.logger = Rails.logger
end
