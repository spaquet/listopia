# app/services/resilient_ruby_llm_service.rb

require "net/http"
require "timeout"

class ResilientRubyLlmService
  include ActiveModel::Model
  include ActiveModel::Attributes

  # Use existing RubyLLM and MCP configuration instead of duplicating
  def self.ruby_llm_config
    RubyLLM.configuration
  end

  def self.mcp_config
    Rails.application.config.mcp
  end

  def self.error_recovery_config
    Rails.application.config.mcp.error_recovery
  end

  # API health status tracking
  class ApiHealthMonitor
    def initialize
      @failure_count = 0
      @success_count = 0
      @last_success = nil
      @last_failure = nil
      @response_times = []
    end

    def record_success(response_time)
      @success_count += 1
      @last_success = Time.current
      @response_times << response_time

      # Keep only last 50 response times
      @response_times = @response_times.last(50)

      # Reset failure count on success
      @failure_count = 0
    end

    def record_failure(error)
      @failure_count += 1
      @last_failure = Time.current
      Rails.logger.warn "RubyLLM API failure recorded: #{error.class.name}"
    end

    def healthy?
      return true if @failure_count == 0
      return false if @failure_count >= 5

      # Consider healthy if last success was recent
      @last_success && @last_success > 5.minutes.ago
    end

    def average_response_time
      return 0 if @response_times.empty?
      @response_times.sum / @response_times.length
    end

    def status
      {
        healthy: healthy?,
        failure_count: @failure_count,
        success_count: @success_count,
        last_success: @last_success,
        last_failure: @last_failure,
        average_response_time: average_response_time,
        recent_failures: @failure_count > 0 && (@last_failure && @last_failure > 5.minutes.ago)
      }
    end
  end

  attr_accessor :health_monitor, :circuit_breaker, :request_logger

  def initialize
    @health_monitor = ApiHealthMonitor.new
    @circuit_breaker = ErrorRecoveryService::CircuitBreaker.new(
      failure_threshold: self.class.error_recovery_config.circuit_breaker_threshold,
      recovery_timeout: self.class.error_recovery_config.circuit_breaker_timeout.seconds,
      expected_errors: [ RubyLLM::Error, Net::TimeoutError, Faraday::Error ]
    )
    @request_logger = RequestLogger.new
    @logger = Rails.logger
  end

  # Main method to make resilient RubyLLM API calls
  def resilient_ask(chat, message_content, **options)
    validate_inputs!(chat, message_content)

    request_start = Time.current
    request_id = generate_request_id

    @request_logger.log_request(request_id, chat.id, message_content, options)

    # Check API health before making request
    unless @health_monitor.healthy?
      @logger.warn "API health check failed, but proceeding with request"
    end

    result = nil
    error_recovery = ErrorRecoveryService.new(user: chat.user, chat: chat)

    # Use RubyLLM's configured max_retries instead of our own
    max_attempts = self.class.ruby_llm_config.max_retries || 3
    attempt = 0

    while attempt < max_attempts
      attempt += 1

      begin
        @logger.info "RubyLLM API call attempt #{attempt}/#{max_attempts} for chat #{chat.id}"

        # Use circuit breaker to protect against cascading failures
        result = @circuit_breaker.call do
          make_api_call_with_timeout(chat, message_content, options)
        end

        # Record successful call
        response_time = Time.current - request_start
        @health_monitor.record_success(response_time)
        @request_logger.log_success(request_id, response_time, result)

        @logger.info "RubyLLM API call succeeded on attempt #{attempt} for chat #{chat.id}"
        return result

      rescue ErrorRecoveryService::ServiceUnavailableError => e
        @logger.error "Service unavailable (circuit breaker open): #{e.message}"
        return handle_service_unavailable(chat, message_content, error_recovery)

      rescue RubyLLM::BadRequestError => e
        @health_monitor.record_failure(e)
        @request_logger.log_error(request_id, e, attempt)

        # Don't retry bad request errors - they won't succeed
        if conversation_structure_error?(e)
          @logger.warn "Conversation structure error detected, attempting recovery"
          return handle_conversation_error(e, chat, message_content, error_recovery)
        else
          @logger.error "Bad request error, not retrying: #{e.message}"
          raise e
        end

      rescue RubyLLM::RateLimitError => e
        @health_monitor.record_failure(e)
        @request_logger.log_error(request_id, e, attempt)

        if attempt < max_attempts
          # Use RubyLLM's configured retry settings
          delay = calculate_ruby_llm_backoff(attempt)
          @logger.info "Rate limited, waiting #{delay}s before retry #{attempt + 1}"
          sleep(delay)
          next
        else
          @logger.error "Rate limit exceeded after #{attempt} attempts"
          raise e
        end

      rescue RubyLLM::Error, Net::TimeoutError, Faraday::Error => e
        @health_monitor.record_failure(e)
        @request_logger.log_error(request_id, e, attempt)

        if attempt < max_attempts
          # Use RubyLLM's retry configuration
          delay = calculate_ruby_llm_backoff(attempt)
          @logger.info "API error (#{e.class.name}), retrying in #{delay}s (attempt #{attempt + 1})"
          sleep(delay)
          next
        else
          @logger.error "API call failed after #{attempt} attempts: #{e.message}"
          return handle_api_failure(e, chat, message_content, error_recovery)
        end

      rescue => e
        @health_monitor.record_failure(e)
        @request_logger.log_error(request_id, e, attempt)

        @logger.error "Unexpected error in RubyLLM call: #{e.class.name} - #{e.message}"
        @logger.error e.backtrace.join("\n")

        if attempt < max_attempts && retryable_error?(e)
          delay = calculate_ruby_llm_backoff(attempt)
          @logger.info "Retrying unexpected error in #{delay}s"
          sleep(delay)
          next
        else
          return handle_unexpected_error(e, chat, message_content, error_recovery)
        end
      end
    end

    # Should not reach here, but handle gracefully
    handle_max_retries_exceeded(chat, message_content, error_recovery)
  end

  # Get comprehensive API health status
  def health_status
    {
      api_health: @health_monitor.status,
      circuit_breaker: @circuit_breaker.status,
      config: @config.except(:circuit_breaker_timeout), # Don't expose timeout object
      uptime: uptime_status
    }
  end

  # Manual health check endpoint
  def perform_health_check!
    @logger.info "Performing manual RubyLLM health check"

    begin
      start_time = Time.current

      # Create a minimal test chat for health check
      test_response = make_health_check_request

      response_time = Time.current - start_time
      @health_monitor.record_success(response_time)

      @logger.info "Health check passed (#{response_time.round(2)}s)"
      { healthy: true, response_time: response_time }

    rescue => e
      @health_monitor.record_failure(e)
      @logger.error "Health check failed: #{e.class.name} - #{e.message}"

      {
        healthy: false,
        error: e.class.name,
        message: e.message,
        timestamp: Time.current
      }
    end
  end

  private

  def validate_inputs!(chat, message_content)
    raise ArgumentError, "Chat cannot be nil" if chat.nil?
    raise ArgumentError, "Message content cannot be empty" if message_content.blank?
    raise ArgumentError, "Chat must have a user" if chat.user.nil?
  end

  def make_api_call_with_timeout(chat, message_content, options)
    # Set up timeout for the API call
    timeout_duration = options[:timeout] || @config[:request_timeout]

    Timeout.timeout(timeout_duration) do
      # Pre-process chat for API call
      prepare_chat_for_api_call!(chat)

      # Make the actual RubyLLM API call
      response = chat.ask(message_content, **options)

      # Post-process and validate response
      validate_api_response!(response)

      response
    end
  rescue Timeout::Error => e
    raise Net::TimeoutError, "API call timed out after #{timeout_duration} seconds"
  end

  def prepare_chat_for_api_call!(chat)
    # Ensure chat is in a good state before making API call
    chat.clean_conversation_for_api_call! if chat.respond_to?(:clean_conversation_for_api_call!)

    # Validate basic chat structure
    unless chat.model_id.present?
      chat.update!(model_id: Rails.application.config.mcp.model)
    end
  end

  def validate_api_response!(response)
    # Basic response validation
    return unless response

    if response.respond_to?(:content) && response.content.blank?
      @logger.warn "Received empty response content from API"
    end
  end

  def calculate_exponential_backoff(attempt)
    base_delay = @config[:base_delay]
    exponential_base = @config[:exponential_base]
    max_delay = @config[:max_delay]

    delay = base_delay * (exponential_base ** (attempt - 1))
    delay = [ delay, max_delay ].min

    # Add jitter to avoid thundering herd
    if @config[:jitter]
      jitter_range = delay * 0.1
      delay += rand(-jitter_range..jitter_range)
    end

    delay.round(2)
  end

  def calculate_rate_limit_delay(error, attempt)
    # Try to extract retry-after header or use exponential backoff
    if error.respond_to?(:response) && error.response
      retry_after = error.response.headers["retry-after"]
      if retry_after
        return retry_after.to_i + rand(1..3) # Add small jitter
      end
    end

    # Fallback to exponential backoff with higher base delay for rate limits
    base_delay = @config[:base_delay] * 2 # Double the base delay for rate limits
    delay = base_delay * (@config[:exponential_base] ** (attempt - 1))
    [ delay, @config[:max_delay] ].min
  end

  def conversation_structure_error?(error)
    error_patterns = [
      /tool_calls.*must be followed by tool messages/i,
      /tool_call_id.*did not have response messages/i,
      /assistant message.*tool_calls.*must be followed/i,
      /invalid.*parameter.*messages/i
    ]

    error_patterns.any? { |pattern| error.message.match?(pattern) }
  end

  def retryable_error?(error)
    retryable_errors = [
      Net::TimeoutError,
      Faraday::TimeoutError,
      Faraday::ConnectionFailed,
      Errno::ECONNREFUSED,
      Errno::EHOSTUNREACH,
      SocketError
    ]

    retryable_errors.any? { |klass| error.is_a?(klass) }
  end

  def handle_conversation_error(error, chat, message_content, error_recovery)
    @logger.warn "Handling conversation structure error for chat #{chat.id}"

    recovery_result = error_recovery.recover_from_error(
      error,
      original_message: message_content,
      attempt_count: 0
    )

    case recovery_result[:action]
    when :use_recovery_branch, :use_fresh_chat
      # Switch to new chat and retry
      new_chat = recovery_result[:new_chat]
      resilient_ask(new_chat, message_content)

    when :retry_after_healing
      # Retry with healed conversation
      resilient_ask(chat, message_content)

    else
      # Return user-friendly message
      OpenStruct.new(content: recovery_result[:user_message])
    end
  end

  def handle_service_unavailable(chat, message_content, error_recovery)
    @logger.error "Service unavailable - circuit breaker is open"

    next_attempt = @circuit_breaker.next_attempt_time
    if next_attempt
      wait_time = ((next_attempt - Time.current) / 60).ceil
      message = "Service is temporarily unavailable. Please try again in #{wait_time} minute(s)."
    else
      message = "Service is temporarily unavailable. Please try again later."
    end

    OpenStruct.new(content: message)
  end

  def handle_api_failure(error, chat, message_content, error_recovery)
    @logger.error "API call failed after all retries: #{error.class.name} - #{error.message}"

    recovery_result = error_recovery.recover_from_error(
      error,
      original_message: message_content,
      attempt_count: @config[:max_retries]
    )

    OpenStruct.new(content: recovery_result[:user_message] || "I'm experiencing technical difficulties. Please try again later.")
  end

  def handle_unexpected_error(error, chat, message_content, error_recovery)
    @logger.error "Unexpected error in RubyLLM integration: #{error.class.name} - #{error.message}"

    recovery_result = error_recovery.recover_from_error(
      error,
      original_message: message_content,
      attempt_count: @config[:max_retries]
    )

    OpenStruct.new(content: recovery_result[:user_message] || "An unexpected error occurred. Please try again.")
  end

  def handle_max_retries_exceeded(chat, message_content, error_recovery)
    max_attempts = self.class.ruby_llm_config.max_retries || 3
    @logger.error "Max retries (#{max_attempts}) exceeded for chat #{chat.id}"

    OpenStruct.new(content: "I'm unable to process your request after multiple attempts. Please try again later or contact support if the issue persists.")
  end

  def make_health_check_request
    # Simple health check using RubyLLM's configured client
    # Use the configured default model
    default_model = self.class.ruby_llm_config.default_model || self.class.mcp_config.model

    client = RubyLLM::Client.new
    client.chat(
      model: default_model,
      messages: [ { role: "user", content: "ping" } ],
      max_tokens: 10
    )
  end

  def generate_request_id
    "req_#{SecureRandom.hex(8)}"
  end

  def uptime_status
    # Simple uptime tracking - could be enhanced with more sophisticated monitoring
    {
      started_at: @started_at ||= Time.current,
      uptime_seconds: Time.current - (@started_at ||= Time.current),
      healthy_percentage: calculate_health_percentage
    }
  end

  def calculate_health_percentage
    total_calls = @health_monitor.instance_variable_get(:@success_count) +
                  @health_monitor.instance_variable_get(:@failure_count)

    return 100.0 if total_calls == 0

    success_rate = (@health_monitor.instance_variable_get(:@success_count).to_f / total_calls) * 100
    success_rate.round(2)
  end

  # Request logging for debugging and monitoring
  class RequestLogger
    def initialize
      @requests = {}
    end

    def log_request(request_id, chat_id, message_content, options)
      @requests[request_id] = {
        chat_id: chat_id,
        message_length: message_content.length,
        options: options.except(:sensitive_data), # Don't log sensitive data
        started_at: Time.current,
        attempts: []
      }
    end

    def log_error(request_id, error, attempt)
      return unless @requests[request_id]

      @requests[request_id][:attempts] << {
        attempt: attempt,
        error_class: error.class.name,
        error_message: error.message,
        timestamp: Time.current
      }
    end

    def log_success(request_id, response_time, result)
      return unless @requests[request_id]

      @requests[request_id].merge!(
        completed_at: Time.current,
        response_time: response_time,
        success: true,
        response_length: result.respond_to?(:content) ? result.content&.length : nil
      )
    end

    def get_request_log(request_id)
      @requests[request_id]
    end

    def cleanup_old_logs!
      cutoff = 1.hour.ago
      @requests.delete_if { |_, data| data[:started_at] < cutoff }
    end
  end
end
