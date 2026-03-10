# config/initializers/prosopite.rb

if Rails.env.development? || Rails.env.test?
  Prosopite.enabled = true                # usually default true anyway

  # Where to send N+1 warnings
  Prosopite.stderr_logger    = true       # ← to STDERR (visible in ./bin/dev console)
  # Prosopite.prosopite_logger = true     # ← to log/prosopite.log (alternative or both)

  # Optional: raise on N+1 in dev/test (great for CI/tests)
  # Prosopite.raise = true

  # Optional tuning
  Prosopite.min_n_queries = 3             # default is probably 2 or 3
  # Prosopite.backtrace_cleaner = Rails.backtrace_cleaner  # or custom
end
