Prosopite.tap do |prosopite|
  prosopite.enabled = Rails.env.development?
  prosopite.stderr = true      # Log to STDERR
  prosopite.raise = false      # Don't raise in dev (annoying)
  prosopite.notify = true      # Show notifications
  prosopite.auto_explain = true
end
