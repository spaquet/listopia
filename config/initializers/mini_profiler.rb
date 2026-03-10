# config/initializers/mini_profiler.rb
if Rails.env.development? && defined?(Rack::MiniProfiler)
  Rack::MiniProfiler.config.disable_caching     = false
  Rack::MiniProfiler.config.backtrace_includes  = /listopia/   # ← update regex to match your app name if needed
  Rack::MiniProfiler.config.max_sql_param_length = 5000   # or 10000, whatever you prefer
  # other nice defaults:
  # Rack::MiniProfiler.config.position = 'bottom-right'
  # Rack::MiniProfiler.config.start_hidden = true   # if you don't always want the badge
end
