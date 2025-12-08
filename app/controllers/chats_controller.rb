# app/controllers/chats_controller.rb
#
# Controller for managing unified chat conversations
# Handles chat creation, viewing, message submission, and deletion

class ChatsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_chat, except: [ :index, :create ]
  before_action :authorize_chat, except: [ :index, :create ]

  # List all chats for current user
  def index
    @chats = current_user.chats.by_organization(current_organization).recent.page(params[:page]).per(20)
  end

  # View single chat
  def show
    @messages = @chat.recent_messages(50)
    @chat_context = @chat.build_context(location: :chat_view)

    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end

  # Create new chat
  def create
    focused_resource = find_focused_resource(params[:focused_resource_type], params[:focused_resource_id])

    @chat = current_user.chats.create!(
      organization: current_organization,
      focused_resource: focused_resource
    )

    @chat_context = @chat.build_context(location: params[:location] || :dashboard)
    @messages = []

    respond_to do |format|
      format.turbo_stream { render action: :create }
      format.html { redirect_to chat_path(@chat) }
    end
  end

  # Submit message to chat
  def create_message
    message_params = params.require(:message).permit(:content)
    content = message_params[:content].strip

    return if content.blank?

    # SECURITY CHECK 1: Detect prompt injection attempts
    injection_detector = PromptInjectionDetector.new(message: content, context: @chat.focused_resource)
    injection_result = injection_detector.call

    if injection_result[:detected] && injection_result[:risk_level] == "high"
      create_security_log(
        violation_type: :prompt_injection,
        action_taken: :blocked,
        detected_patterns: injection_result[:patterns],
        risk_score: injection_result[:risk_score],
        details: "High-risk prompt injection attempt detected"
      )
      return render_security_error("Suspicious input detected and blocked for security reasons", 422)
    end

    if injection_result[:detected]
      create_security_log(
        violation_type: :prompt_injection,
        action_taken: :warned,
        detected_patterns: injection_result[:patterns],
        risk_score: injection_result[:risk_score],
        details: "Medium-risk prompt injection attempt - message allowed"
      )
    end

    # Create user message
    @user_message = Message.create_user(
      chat: @chat,
      user: current_user,
      content: content
    )

    # SECURITY CHECK 2: Check content moderation (OpenAI)
    moderation_service = ContentModerationService.new(
      content: content,
      user: current_user,
      chat: @chat
    )
    moderation_result = moderation_service.call

    if moderation_result[:flagged]
      @user_message.update(blocked: true)
      violation_type = categorize_moderation_violation(moderation_result[:categories])
      create_security_log(
        violation_type: violation_type,
        action_taken: :blocked,
        message: @user_message,
        detected_patterns: moderation_result[:categories].select { |_k, v| v }.keys.map(&:to_s),
        moderation_scores: moderation_result[:scores],
        details: "Content flagged by OpenAI moderation"
      )

      # Check if auto-archive threshold is exceeded
      ModerationLog.check_auto_archive(@chat, current_organization)

      return render_security_error("This message violates content policies and cannot be sent", 422)
    end

    # Process message normally (handle commands, generate response, etc.)
    @assistant_message = process_message(@user_message)

    @chat_context = @chat.build_context(location: :dashboard)

    respond_to do |format|
      format.turbo_stream { render action: :create_message }
      format.json { render json: { success: true, message_id: @user_message.id } }
    end
  end

  # Delete chat
  def destroy
    @chat.soft_delete!

    respond_to do |format|
      format.html { redirect_to chats_url, notice: "Chat deleted" }
      format.turbo_stream
    end
  end

  # Archive chat
  def archive
    @chat.archive!

    respond_to do |format|
      format.html { redirect_to chats_url, notice: "Chat archived" }
      format.turbo_stream
    end
  end

  # Restore archived chat
  def restore
    @chat.restore!

    respond_to do |format|
      format.html { redirect_to chat_path(@chat), notice: "Chat restored" }
      format.turbo_stream
    end
  end

  private

  def set_chat
    @chat = Chat.find(params[:id])
  end

  def authorize_chat
    authorize @chat
  end

  def find_focused_resource(type, id)
    return nil unless type.present? && id.present?

    case type
    when "List"
      List.find(id)
    when "Team"
      Team.find(id)
    when "Organization"
      Organization.find(id)
    else
      nil
    end
  end

  def process_message(user_message)
    # Check if message is a command
    if user_message.content.start_with?("/")
      handle_command(user_message)
      nil  # Commands don't return a message
    else
      # For now, just acknowledge the message
      # In full implementation, this would call RubyLLM to generate a response
      add_placeholder_response(user_message)
    end
  end

  def handle_command(user_message)
    command_parts = user_message.content.split(" ", 2)
    command = command_parts[0]
    args = command_parts[1].to_s

    case command
    when "/search"
      handle_search_command(user_message, args)
    when "/help"
      handle_help_command(user_message)
    when "/clear"
      handle_clear_command
    when "/new"
      # This would trigger creating a new chat in the UI
      Message.create_system(@chat, "Creating new conversation...")
    else
      Message.create_system(
        @chat,
        "Unknown command: #{command}. Type /help for available commands."
      )
    end
  end

  def handle_search_command(user_message, query)
    query = query.strip

    if query.blank?
      Message.create_system(
        @chat,
        "Please provide a search query. Example: /search budget"
      )
      return
    end

    # Perform search
    results = Search::Service.new(current_user, current_organization).search(query)

    # Create search results template message
    template_data = {
      query: query,
      results: results.map { |result| format_search_result(result) },
      total_count: results.length,
      search_type: "all"
    }

    Message.create_templated(
      chat: @chat,
      template_type: "search_results",
      template_data: template_data
    )
  end

  def handle_help_command(user_message)
    help_text = <<~HELP
      **Available Commands:**
      - `/search <query>` - Search your lists and items
      - `/browse` - Browse all available lists
      - `/help` - Show this help message
      - `/clear` - Clear chat history
      - `/new` - Start a new conversation

      **Tips:**
      - Start a normal message to chat with the assistant
      - Use markdown for formatting in your messages
      - Rate responses to help improve the assistant
    HELP

    Message.create_system(@chat, help_text)
  end

  def handle_clear_command
    @chat.messages.destroy_all
    Message.create_system(@chat, "Chat history cleared.")
  end

  def add_placeholder_response(user_message)
    # Use ChatCompletionService to generate AI response with RubyLLM
    service = ChatCompletionService.new(@chat, user_message, @chat_context)
    result = service.call

    if result.success?
      result.data  # Returns the assistant message
    else
      # Fallback response if LLM fails
      Rails.logger.warn("Chat completion failed: #{result.errors.join(', ')}")
      Message.create_assistant(
        chat: @chat,
        content: "I encountered an issue processing your message. Please try again."
      )
    end
  end

  def format_search_result(result)
    {
      title: result[:title],
      description: result[:description],
      url: result[:url],
      type: result[:type],
      owner: result[:owner],
      created_at: result[:created_at],
      item_count: result[:item_count]
    }
  end

  # Create security/moderation log entry
  def create_security_log(violation_type:, action_taken:, message: nil, **details)
    ModerationLog.create!(
      chat: @chat,
      message: message,
      user: current_user,
      organization: current_organization,
      violation_type: violation_type,
      action_taken: action_taken,
      **details
    )
  rescue StandardError => e
    Rails.logger.error("Failed to create security log: #{e.message}")
  end

  # Render error for blocked messages
  def render_security_error(error_message, status = 422)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.replace(
          "unified-chat [data-unified-chat-target='messagesContainer']",
          partial: "shared/chat_message",
          locals: {
            message: create_error_message(error_message),
            chat_context: @chat.build_context(location: :dashboard)
          }
        ), status: status
      end
      format.json { render json: { error: error_message }, status: status }
    end
  end

  # Create a temporary error message object (not saved to DB)
  def create_error_message(text)
    Message.new(
      content: text,
      role: :tool,
      template_type: "error",
      metadata: { error_message: text }
    )
  end

  # Categorize moderation violation based on flagged categories
  def categorize_moderation_violation(flagged_categories)
    return :other if flagged_categories.blank?

    # Map OpenAI moderation categories to our violation types
    if flagged_categories[:self_harm] || flagged_categories[:self_harm_intent] || flagged_categories[:self_harm_instructions]
      :self_harm
    elsif flagged_categories[:sexual_minors]
      :sexual_content
    elsif flagged_categories[:sexual]
      :sexual_content
    elsif flagged_categories[:violence_graphic]
      :violence
    elsif flagged_categories[:violence]
      :violence
    elsif flagged_categories[:harassment_threatening] || flagged_categories[:harassment]
      :harassment
    elsif flagged_categories[:hate_threatening]
      :hate_speech
    elsif flagged_categories[:hate]
      :hate_speech
    else
      :other
    end
  end
end
