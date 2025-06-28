# app/middleware/conversation_error_middleware.rb
class ConversationErrorMiddleware
  def initialize(app)
    @app = app
    @enabled = Rails.env.production? || ENV['CONVERSATION_ERROR_MIDDLEWARE'] == 'true'
  end

  def call(env)
    return @app.call(env) unless @enabled

    response = @app.call(env)
    response
  rescue ConversationStateManager::ConversationError => e
    # Log the error with request context
    Rails.logger.error "Conversation error in request: #{e.message}"
    Rails.logger.error "Request path: #{env['REQUEST_PATH']}"
    Rails.logger.error "User ID: #{env['warden']&.user&.id}"

    # In development, you might want to re-raise for better debugging
    if Rails.env.development? && ENV['DEBUG_CONVERSATION_ERRORS'] == 'true'
      raise e
    end

    # Return a user-friendly error response based on request format
    if json_request?(env)
      [500, {'Content-Type' => 'application/json'},
       [{ error: "I encountered a conversation error. Please refresh and try again." }.to_json]]
    else
      [500, {'Content-Type' => 'text/html'},
       ["<html><body><h1>Conversation Error</h1><p>Please refresh and try again.</p></body></html>"]]
    end
  end

  private

  def json_request?(env)
    env['HTTP_ACCEPT']&.include?('application/json') ||
    env['CONTENT_TYPE']&.include?('application/json') ||
    env['REQUEST_PATH']&.include?('/api/')
  end
end
