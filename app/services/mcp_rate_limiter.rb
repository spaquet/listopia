# app/services/mcp_rate_limiter.rb
class McpRateLimiter
  HOUR_LIMIT = Rails.application.config.mcp.rate_limit_per_hour
  MINUTE_LIMIT = Rails.application.config.mcp.rate_limit_per_minute

  def initialize(user)
    @user = user
    @redis = Rails.cache.redis if Rails.cache.respond_to?(:redis)
  end

  def check_rate_limit!
    check_hourly_limit!
    check_minute_limit!
  end

  def remaining_hourly_requests
    HOUR_LIMIT - hourly_count
  end

  def remaining_minute_requests
    MINUTE_LIMIT - minute_count
  end

  # This method needs to be public so it can be called from McpService
  def increment_counters!
    # Increment hourly counter
    hourly_key = "mcp_hourly_#{@user.id}_#{current_hour}"
    Rails.cache.write(hourly_key, hourly_count + 1, expires_in: 1.hour)

    # Increment minute counter
    minute_key = "mcp_minute_#{@user.id}_#{current_minute}"
    Rails.cache.write(minute_key, minute_count + 1, expires_in: 1.minute)
  end

  private

  def check_hourly_limit!
    if hourly_count >= HOUR_LIMIT
      raise RateLimitError, "Hourly rate limit exceeded. Try again in #{time_until_hour_reset} minutes."
    end
  end

  def check_minute_limit!
    if minute_count >= MINUTE_LIMIT
      raise RateLimitError, "Rate limit exceeded. Please wait a minute before trying again."
    end
  end

  def hourly_count
    key = "mcp_hourly_#{@user.id}_#{current_hour}"
    count = Rails.cache.read(key) || 0
    count.to_i
  end

  def minute_count
    key = "mcp_minute_#{@user.id}_#{current_minute}"
    count = Rails.cache.read(key) || 0
    count.to_i
  end

  def current_hour
    Time.current.strftime("%Y%m%d%H")
  end

  def current_minute
    Time.current.strftime("%Y%m%d%H%M")
  end

  def time_until_hour_reset
    60 - Time.current.min
  end

  class RateLimitError < StandardError; end
end
