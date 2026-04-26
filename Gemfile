source "https://rubygems.org"

# Bundle edge Rails instead: gem "rails", github: "rails/rails", branch: "main"
gem "rails", "~> 8.1.0"
# The modern asset pipeline for Rails [https://github.com/rails/propshaft]
gem "propshaft"
# Use postgresql as the database for Active Record
gem "pg", "~> 1.6"
# Use the Puma web server [https://github.com/puma/puma]
gem "puma", ">= 5.0"
# Bundle and transpile JavaScript [https://github.com/rails/jsbundling-rails]
gem "jsbundling-rails"
# Hotwire's SPA-like page accelerator [https://turbo.hotwired.dev]
gem "turbo-rails"
# Hotwire's modest JavaScript framework [https://stimulus.hotwired.dev]
gem "stimulus-rails"
# Bundle and process CSS [https://github.com/rails/cssbundling-rails]
gem "cssbundling-rails"
# Build JSON APIs with ease [https://github.com/rails/jbuilder]
gem "jbuilder"

# Use Active Model has_secure_password [https://guides.rubyonrails.org/active_model_basics.html#securepassword]
gem "bcrypt", "~> 3.1.21"

gem "pundit" # Authorization library for Rails applications
gem "rolify" # Role management library for Rails applications

# Auditing and versioning for Active Record models [https://github.com/palkan/logidze]
gem "logidze"

# Soft delete for Active Record models [https://github.com/jhawthorn/discard]
gem "discard"

# Use Redis as a cache store [https://guides.rubyonrails.org/caching_with_rails.html#redis-cache-store]
# gem "redis", "~> 4.0"

# Use Sidekiq for background jobs [

# Windows does not include zoneinfo files, so bundle the tzinfo-data gem
gem "tzinfo-data", platforms: %i[ windows jruby ]

# Use the database-backed adapters for Rails.cache, Active Job, and Action Cable
gem "solid_cache"
# gem "solid_queue"
# Experimental fiber based async execution mode for Solid Queue (requires Ruby 4+ and Rails 8.1+)
# read me [https://paolino.me/solid-queue-doesnt-need-a-thread-per-job/]
gem "solid_queue", git: "https://github.com/crmne/solid_queue.git", branch: "async-worker-execution-mode"
gem "solid_cable"

# Pagination
gem "pagy"

# Searching and filtering
gem "pg_search"

# Notification
gem "noticed"

# Positioning, ordering of the lists and list items
gem "positioning"

# AI/LLM Integration
gem "ruby_llm"
gem "ruby_llm-schema"  # Structured output with schemas
gem "neighbor"

# JWT for OAuth token handling
gem "jwt"

# JSON processing for MCP responses
gem "multi_json"

# CSV processing (required for Ruby 3.4+)
gem "csv"

# Markdown rendering with syntax highlighting
gem "redcarpet"
gem "rouge"

# Reduces boot times through caching; required in config/boot.rb
gem "bootsnap", require: false

# Deploy this application anywhere as a Docker container [https://kamal-deploy.org]
gem "kamal", require: false

# Add HTTP asset caching/compression and X-Sendfile acceleration to Puma [https://github.com/basecamp/thruster/]
gem "thruster", require: false

# Add support to friendly URLs for Active Record models [https://github.com/norman/friendly_id]
# This gem allows you to create human-readable URLs for your models, which is useful for SEO and user experience.
# It provides a way to generate slugs based on model attributes, making URLs more descriptive.
gem "friendly_id"

# Add tag support to Active Record models [https://github.com/mbleigh/acts-as-taggable-on]
# gem "acts-as-taggable-on", "~> 12.0"
gem "acts-as-taggable-on", github: "mbleigh/acts-as-taggable-on", branch: "master"

# Use Active Storage variants [https://guides.rubyonrails.org/active_storage_overview.html#transforming-images]
gem "image_processing", "~> 1.2"

group :development, :test do
  # See https://guides.rubyonrails.org/debugging_rails_applications.html#debugging-with-the-debug-gem
  gem "debug", platforms: %i[ mri windows ], require: "debug/prelude"

  # Static analysis for security vulnerabilities [https://brakemanscanner.org/]
  gem "brakeman", require: false

  # Omakase Ruby styling [https://github.com/rails/rubocop-rails-omakase/]
  gem "rubocop-rails-omakase", require: false

  # RSpec for testing
  gem "rspec-rails"
  gem "factory_bot_rails"
  gem "faker"
end

group :development do
  # Use console on exceptions pages [https://github.com/rails/web-console]
  gem "web-console"
  gem "letter_opener"
  gem "dotenv-rails"
  gem "annotaterb"

  # Track N+1 queries and unused eager loading [https://github.com/flyerhzm/bullet]
  gem "bullet"

  # Rack mini profiler for performance insights [https://github.com/MiniProfiler/rack-mini-profiler]
  gem "rack-mini-profiler"

  # StackProf for sampling call stacks and identifying bottlenecks []
  gem "stackprof"

  # Prosopite for tracking object allocations and memory usage [https://github.com/charkost/prosopite]
  gem "prosopite"

  # Memory profiler for detailed memory usage reports [
  gem "memory_profiler"
end

group :test do
  # Use system testing [https://guides.rubyonrails.org/testing.html#system-testing]
  gem "capybara"
  gem "selenium-webdriver"
  gem "cuprite"

  # Used to test rubyllm integrations
  gem "vcr", "~> 6.2"
  gem "webmock", "~> 3.18"

  # Code coverage reporting
  gem "simplecov", "~> 0.22.0", require: false

  # Additional RSpec gems
  gem "shoulda-matchers", "~> 7.0" # For better model validations testing
  gem "pundit-matchers", "~> 4.0.0" # For Pundit authorization matchers
  gem "database_cleaner-active_record" # For cleaning test database
  gem "rails-controller-testing" # For testing controllers properly
  gem "rspec-retry" # For flaky test retries
  gem "timecop" # For time-based testing
end
