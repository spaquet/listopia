# app/services/error_recovery_service.rb
class ErrorRecoveryService
  include ActiveModel::Model
  include ActiveModel::Attributes

  # Error classification constants
  ERROR_CATEGORIES = {
    # API-related errors
    rate_limit: {
      patterns: [ /rate limit/i, /too many requests/i, /quota exceeded/i ],
      severity: :warning,
      recoverable: true,
      strategy: :exponential_backoff
    },

    # Conversation structure errors
    conversation_structure: {
      patterns: [
        /tool_calls.*must be followed by tool messages/i,
        /tool_call_id.*did not have response messages/i,
        /assistant message.*tool_calls.*must be followed/i,
        /invalid.*parameter.*messages/i
      ],
      severity: :high,
      recoverable: true,
      strategy: :conversation_repair
    },

    # Authentication/Authorization errors
    auth_error: {
      patterns: [ /unauthorized/i, /authentication failed/i, /invalid.*token/i ],
      severity: :high,
      recoverable: false,
      strategy: :user_intervention
    },

    # Network/Connection errors
    network_error: {
      patterns: [ /network/i, /connection/i, /timeout/i, /unreachable/i ],
      severity: :medium,
      recoverable: true,
      strategy: :retry_with_backoff
    },

    # Service unavailable
    service_unavailable: {
      patterns: [ /service unavailable/i, /server error/i, /internal error/i ],
      severity: :high,
      recoverable: true,
      strategy: :circuit_breaker
    },

    # Validation errors
    validation_error: {
      patterns: [ /validation/i, /invalid input/i, /bad request/i ],
      severity: :low,
      recoverable: false,
      strategy: :user_correction
    }
  }.freeze

  attr_accessor :user, :chat, :context

  def initialize(user:, chat: nil, context: {})
    @user = user
    @chat = chat
    @context = context
    @logger = Rails.logger
    @recovery_attempts = Hash.new(0)
  end

  # Main error recovery entry point
  def recover_from_error(error, original_message: nil, attempt_count: 0)
    error_info = classify_error(error)

    @logger.info "Recovering from #{error_info[:category]} error (attempt #{attempt_count + 1})"

    # Track recovery attempts
    recovery_key = "#{error_info[:category]}_#{@chat&.id}"
    @recovery_attempts[recovery_key] += 1

    # Check if we've exceeded max recovery attempts
    if @recovery_attempts[recovery_key] > max_attempts_for_category(error_info[:category])
      return handle_max_attempts_exceeded(error_info, original_message)
    end

    # Apply recovery strategy
    case error_info[:strategy]
    when :exponential_backoff
      recover_with_exponential_backoff(error, original_message, attempt_count)
    when :conversation_repair
      recover_with_conversation_repair(error, original_message)
    when :retry_with_backoff
      recover_with_simple_backoff(error, original_message, attempt_count)
    when :circuit_breaker
      recover_with_circuit_breaker(error, original_message)
    when :user_intervention
      handle_user_intervention_required(error_info)
    when :user_correction
      handle_user_correction_required(error_info)
    else
      handle_unknown_error(error, original_message)
    end
  end

  # Classify error based on patterns and context
  def classify_error(error)
    error_message = extract_error_message(error)

    ERROR_CATEGORIES.each do |category, config|
      if config[:patterns].any? { |pattern| error_message.match?(pattern) }
        return {
          category: category,
          severity: config[:severity],
          recoverable: config[:recoverable],
          strategy: config[:strategy],
          original_error: error,
          message: error_message
        }
      end
    end

    # Default classification for unknown errors
    {
      category: :unknown,
      severity: :medium,
      recoverable: true,
      strategy: :retry_with_backoff,
      original_error: error,
      message: error_message
    }
  end

  # Recovery strategies

  def recover_with_exponential_backoff(error, original_message, attempt_count)
    delay = calculate_exponential_backoff(attempt_count)

    @logger.info "Applying exponential backoff: #{delay}s delay"

    {
      strategy: :exponential_backoff,
      delay: delay,
      retry_message: original_message,
      user_message: "Rate limit reached. Retrying in #{delay} seconds...",
      recoverable: true
    }
  end

  def recover_with_conversation_repair(error, original_message)
    return handle_no_chat_context if @chat.nil?

    @logger.info "Attempting conversation repair for chat #{@chat.id}"

    begin
      # Use ChatStateManager for advanced recovery
      state_manager = ChatStateManager.new(@chat)

      # Try validation and healing first
      result = state_manager.validate_and_heal_state!

      case result[:status]
      when :healthy
        @logger.info "Chat was already healthy, proceeding with original message"
        {
          strategy: :conversation_repair,
          action: :proceed,
          retry_message: original_message,
          user_message: "Conversation validated. Retrying your request...",
          recoverable: true
        }

      when :healed
        @logger.info "Successfully healed conversation: #{result[:actions_taken].join(', ')}"
        {
          strategy: :conversation_repair,
          action: :retry_after_healing,
          retry_message: original_message,
          user_message: "Fixed conversation issues. Retrying your request...",
          actions_taken: result[:actions_taken],
          recoverable: true
        }

      when :recovery_branch_created
        @logger.info "Created recovery branch: #{result[:recovery_chat].id}"
        {
          strategy: :conversation_repair,
          action: :use_recovery_branch,
          new_chat: result[:recovery_chat],
          retry_message: original_message,
          user_message: "Started a fresh conversation to resolve technical issues. Continuing with your request...",
          original_chat_id: @chat.id,
          recoverable: true
        }
      end

    rescue ChatStateManager::StateCorruptionError => e
      @logger.error "State corruption detected: #{e.message}"
      create_fresh_chat_recovery(original_message, "conversation state corruption")

    rescue => e
      @logger.error "Conversation repair failed: #{e.message}"
      create_fresh_chat_recovery(original_message, "repair failure")
    end
  end

  def recover_with_simple_backoff(error, original_message, attempt_count)
    delay = [ 2 ** attempt_count, 30 ].min # Max 30 seconds

    {
      strategy: :simple_backoff,
      delay: delay,
      retry_message: original_message,
      user_message: "Connection issue detected. Retrying in #{delay} seconds...",
      recoverable: true
    }
  end

  def recover_with_circuit_breaker(error, original_message)
    circuit_breaker = get_circuit_breaker

    if circuit_breaker.open?
      @logger.warn "Circuit breaker is open, service likely unavailable"
      return {
        strategy: :circuit_breaker,
        action: :service_unavailable,
        user_message: "Service is temporarily unavailable. Please try again in a few minutes.",
        retry_after: circuit_breaker.next_attempt_time,
        recoverable: false
      }
    end

    circuit_breaker.record_failure

    {
      strategy: :circuit_breaker,
      action: :retry_with_circuit_breaker,
      retry_message: original_message,
      user_message: "Service experiencing issues. Retrying with protective measures...",
      recoverable: true
    }
  end

  def handle_user_intervention_required(error_info)
    @logger.warn "User intervention required for #{error_info[:category]} error"

    {
      strategy: :user_intervention,
      action: :require_user_action,
      user_message: get_user_intervention_message(error_info[:category]),
      recoverable: false
    }
  end

  def handle_user_correction_required(error_info)
    {
      strategy: :user_correction,
      action: :require_input_correction,
      user_message: "Please check your input and try again. #{error_info[:message]}",
      recoverable: false
    }
  end

  def handle_unknown_error(error, original_message)
    @logger.error "Unknown error encountered: #{error.class.name} - #{error.message}"

    {
      strategy: :unknown_error,
      action: :generic_retry,
      retry_message: original_message,
      user_message: "An unexpected error occurred. Retrying your request...",
      recoverable: true,
      error_class: error.class.name,
      error_message: error.message
    }
  end

  # Context preservation during recovery (using database instead of Redis)
  def preserve_context(additional_context = {})
    preserved_context = {
      timestamp: Time.current.iso8601,
      user_id: @user&.id,
      chat_id: @chat&.id,
      recovery_attempts: @recovery_attempts.dup,
      original_context: @context.dup
    }.merge(additional_context)

    # Store in database with expiration (clean up old records)
    RecoveryContext.create!(
      user: @user,
      chat: @chat,
      context_data: preserved_context,
      expires_at: 1.hour.from_now
    )

    preserved_context
  end

  def restore_context
    return {} unless @user && @chat

    recovery_context = RecoveryContext.where(user: @user, chat: @chat)
                                     .where("expires_at > ?", Time.current)
                                     .order(created_at: :desc)
                                     .first

    return {} unless recovery_context

    recovery_context.context_data || {}
  rescue => e
    @logger.error "Failed to restore context: #{e.message}"
    {}
  end

  # Get recovery statistics for monitoring (using database)
  def recovery_statistics
    {
      total_attempts: @recovery_attempts.values.sum,
      attempts_by_category: @recovery_attempts.dup,
      circuit_breaker_status: get_circuit_breaker.status,
      active_recoveries: count_active_recoveries
    }
  end

  private

  def extract_error_message(error)
    case error
    when String
      error
    when StandardError
      error.message
    when Hash
      error[:message] || error["message"] || error.to_s
    else
      error.to_s
    end
  end

  def max_attempts_for_category(category)
    {
      rate_limit: 3,
      conversation_structure: 2,
      network_error: 5,
      service_unavailable: 3,
      unknown: 3
    }[category] || 2
  end

  def calculate_exponential_backoff(attempt_count)
    base_delay = 2
    max_delay = 60
    jitter = rand(0.1..0.3)

    delay = base_delay * (2 ** attempt_count) * (1 + jitter)
    [ delay, max_delay ].min.round(2)
  end

  def get_circuit_breaker
    @circuit_breaker ||= CircuitBreaker.new(
      failure_threshold: 5,
      recovery_timeout: 30.seconds,
      expected_errors: [ RubyLLM::Error, Net::TimeoutError ]
    )
  end

  def handle_max_attempts_exceeded(error_info, original_message)
    @logger.error "Max recovery attempts exceeded for #{error_info[:category]}"

    case error_info[:category]
    when :conversation_structure
      create_fresh_chat_recovery(original_message, "max conversation repair attempts")
    else
      {
        strategy: :max_attempts_exceeded,
        action: :give_up,
        user_message: "Unable to recover from this error after multiple attempts. Please try again later or contact support.",
        error_category: error_info[:category],
        recoverable: false
      }
    end
  end

  def create_fresh_chat_recovery(original_message, reason)
    return handle_no_chat_context if @chat.nil?

    begin
      # Archive problematic chat
      @chat.update!(
        status: "archived",
        title: "#{@chat.title} (Archived - #{reason.titleize} at #{Time.current.strftime('%H:%M')})",
        conversation_state: "error"
      )

      # Create fresh chat
      fresh_chat = @user.chats.create!(
        title: generate_fresh_chat_title,
        status: "active",
        conversation_state: "stable",
        model_id: @chat.model_id || Rails.application.config.mcp.model,
        last_stable_at: Time.current
      )

      @logger.info "Created fresh chat #{fresh_chat.id} due to #{reason}"

      {
        strategy: :fresh_chat_recovery,
        action: :use_fresh_chat,
        new_chat: fresh_chat,
        retry_message: original_message,
        user_message: "Started a fresh conversation to resolve technical issues. Continuing with your request...",
        original_chat_id: @chat.id,
        reason: reason,
        recoverable: true
      }

    rescue => e
      @logger.error "Failed to create fresh chat: #{e.message}"
      {
        strategy: :fresh_chat_recovery,
        action: :failed_to_create_fresh_chat,
        user_message: "Unable to recover from this error. Please refresh the page or contact support.",
        recoverable: false
      }
    end
  end

  def handle_no_chat_context
    {
      strategy: :no_chat_context,
      action: :create_new_chat,
      user_message: "Starting a new conversation...",
      recoverable: true
    }
  end

  def get_user_intervention_message(category)
    case category
    when :auth_error
      "Authentication failed. Please sign in again to continue."
    else
      "This error requires your attention. Please check your settings or contact support."
    end
  end

  def generate_fresh_chat_title
    "Chat #{Time.current.strftime('%m/%d %H:%M')}"
  end

  def count_active_recoveries
    # Count ongoing recovery operations from database
    RecoveryContext.where("expires_at > ?", Time.current).count
  end

  # Simple circuit breaker implementation
  class CircuitBreaker
    attr_reader :failure_threshold, :recovery_timeout, :expected_errors

    def initialize(failure_threshold:, recovery_timeout:, expected_errors: [])
      @failure_threshold = failure_threshold
      @recovery_timeout = recovery_timeout
      @expected_errors = expected_errors
      @failure_count = 0
      @last_failure_time = nil
      @state = :closed # :closed, :open, :half_open
    end

    def open?
      @state == :open
    end

    def closed?
      @state == :closed
    end

    def half_open?
      @state == :half_open
    end

    def record_failure
      @failure_count += 1
      @last_failure_time = Time.current

      if @failure_count >= @failure_threshold
        @state = :open
        Rails.logger.warn "Circuit breaker opened after #{@failure_count} failures"
      end
    end

    def record_success
      @failure_count = 0
      @last_failure_time = nil
      @state = :closed
      Rails.logger.info "Circuit breaker closed after successful operation"
    end

    def call
      case @state
      when :open
        if should_attempt_reset?
          @state = :half_open
          Rails.logger.info "Circuit breaker moving to half-open state"
        else
          raise ServiceUnavailableError, "Circuit breaker is open"
        end
      when :half_open
        # Allow one attempt in half-open state
      end

      begin
        result = yield
        record_success if @state == :half_open
        result
      rescue => error
        record_failure
        raise error
      end
    end

    def status
      {
        state: @state,
        failure_count: @failure_count,
        last_failure_time: @last_failure_time,
        next_attempt_time: next_attempt_time
      }
    end

    def next_attempt_time
      return nil unless @state == :open && @last_failure_time
      @last_failure_time + @recovery_timeout
    end

    private

    def should_attempt_reset?
      @state == :open &&
      @last_failure_time &&
      Time.current >= (@last_failure_time + @recovery_timeout)
    end
  end

  class ServiceUnavailableError < StandardError; end
end
