require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

# Configure RubyLLM BEFORE Rails::Application is inherited
# This ensures acts_as_model, acts_as_chat, acts_as_message are available when models load
require "ruby_llm"

RubyLLM.configure do |config|
  # Use modern RubyLLM 1.8 features
  config.use_new_acts_as = true

  # Rest of the configuration in config/initializers/ruby_llm.rb
end

module Listopia
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.0

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Use UUIDs for primary keys
    config.generators do |g|
      g.orm :active_record, primary_key_type: :uuid
    end

    # Logidze uses DB functions and triggers, hence you need to use SQL format for a schema dump
    # Other Logidze-related config options can be set in the initializer in config/initializers/logidze.rb
    config.active_record.schema_format = :sql

    # Complexity Analysis configuration (existing)
    config.complexity_analysis = ActiveSupport::OrderedOptions.new
    config.complexity_analysis.enabled = ENV.fetch("COMPLEXITY_ANALYSIS_ENABLED", "false") == "true"
    config.complexity_analysis.method = ENV.fetch("COMPLEXITY_ANALYSIS_METHOD", "llm_primary")
    config.complexity_analysis.cultural_adaptation = ENV.fetch("CULTURAL_ADAPTATION", "true") == "true"
    config.complexity_analysis.user_learning = ENV.fetch("USER_LEARNING", "false") == "true"
    config.complexity_analysis.cache_duration = ENV.fetch("COMPLEXITY_CACHE_DURATION", "3600").to_i
    config.complexity_analysis.timeout = ENV.fetch("COMPLEXITY_ANALYSIS_TIMEOUT", "30").to_i
    config.complexity_analysis.fallback_enabled = ENV.fetch("COMPLEXITY_FALLBACK_ENABLED", "true") == "true"
    config.complexity_analysis.debug_logging = ENV.fetch("COMPLEXITY_DEBUG_LOGGING", "false") == "true"
    config.complexity_analysis.error_reporting = ENV.fetch("COMPLEXITY_ERROR_REPORTING", "false") == "true"
    config.complexity_analysis.metrics_enabled = ENV.fetch("COMPLEXITY_METRICS_ENABLED", "false") == "true"
  end
end
