# config/initializers/ruby_llm.rb
require "ruby_llm"

RubyLLM.configure do |config|
  # Configure API keys for the providers you want to use
  config.openai_api_key = ENV.fetch("OPENAI_API_KEY", nil)
  config.anthropic_api_key = ENV.fetch("ANTHROPIC_API_KEY", nil)
  config.gemini_api_key = ENV.fetch("GEMINI_API_KEY", nil)

  # Default models (optional)
  config.default_model = ENV.fetch("LLM_MODEL", "gpt-4.1-nano")
  config.default_embedding_model = ENV.fetch("EMBEDDING_MODEL", "text-embedding-3-large")

  # Timeout settings (optional)
  # config.request_timeout = 60
  # config.read_timeout = 60
end
