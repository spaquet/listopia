# config/initializers/ruby_llm.rb
require "ruby_llm"

RubyLLM.configure do |config|
  config.openai_api_key = ENV["OPENAI_API_KEY"]
  config.anthropic_api_key = ENV["ANTHROPIC_API_KEY"] if ENV["ANTHROPIC_API_KEY"]

  # Use modern RubyLLM 1.8 features
  config.use_new_acts_as = true

  # Set defaults
  config.default_chat_model = "gpt-4.1-nano"
end
