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
    begin
      message_params = params.require(:message).permit(:content)
    rescue ActionController::ParameterMissing
      return render_security_error("Message content is required", 422)
    end

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

    # Parse mentions and references in message
    mention_parser = ChatMentionParser.new(
      message: content,
      user: current_user,
      organization: current_organization
    )
    parse_result = mention_parser.call

    # Store mention and reference metadata
    @user_message.update(
      metadata: {
        mentions: parse_result[:mentions],
        references: parse_result[:references],
        has_mentions: parse_result[:has_mentions],
        has_references: parse_result[:has_references]
      }
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

    @chat_context = @chat.build_context(location: :dashboard)

    # Check if message is a command (instant processing)
    is_command = @user_message.content.start_with?("/")
    auto_submit_commands = [ "/help", "/clear", "/new" ]
    @should_clear_input = is_command && auto_submit_commands.include?(@user_message.content.split(" ").first)

    if is_command
      # Commands are processed synchronously and return immediately with full response
      @assistant_message = process_message(@user_message)

      respond_to do |format|
        format.turbo_stream { render action: :create_message }
        format.json { render json: { success: true, message_id: @user_message.id } }
      end
    else
      # For LLM messages, show loading indicator immediately and process in background
      respond_to do |format|
        format.turbo_stream do
          # First, render the user message and loading indicator
          render action: :create_message_with_loading
        end
        format.json { render json: { success: true, message_id: @user_message.id } }
      end

      # Process LLM response in the background
      ProcessChatMessageJob.perform_later(@user_message.id, @chat.id, current_user.id)
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
      # Return the last created message (the command response)
      @chat.messages.order(:created_at).last
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
    when "/browse"
      handle_browse_command(user_message, args)
    when "/help"
      handle_help_command(user_message)
    when "/clear"
      handle_clear_command
    when "/new"
      # This would trigger creating a new chat in the UI
      Message.create_system(chat: @chat, content: "Creating new conversation...")
    else
      Message.create_system(
        chat: @chat,
        content: "Unknown command: #{command}. Type /help for available commands."
      )
    end
  end

  def handle_search_command(user_message, query)
    query = query.strip

    if query.blank?
      Message.create_system(
        chat: @chat,
        content: "Please provide a search query. Example: /search budget"
      )
      return
    end

    # Perform search using SearchService
    search_result = SearchService.new(query: query, user: current_user).call

    if search_result.failure?
      Message.create_system(
        chat: @chat,
        content: "Search failed: #{search_result.errors.first}"
      )
      return
    end

    results = search_result.data || []

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

  def handle_browse_command(user_message, filter_arg)
    # Get all lists for current user's organization
    lists = policy_scope(List).where(organization_id: current_organization.id)

    # Apply filter if provided
    filter = nil
    if filter_arg.present?
      filter = filter_arg.strip.downcase
      # Validate filter is a valid List status
      if List.statuses.key?(filter)
        lists = lists.where(status: filter)
      end
    end

    # Format for display
    template_data = {
      filter: filter || "all",
      lists: lists.map { |list| {
        id: list.id,
        title: list.title,
        description: list.description,
        status: list.status,
        owner: list.owner.name,
        items_count: list.list_items.count,
        created_at: list.created_at.strftime("%b %d, %Y"),
        url: list_path(list)
      }},
      total_count: lists.count
    }

    # Create browse results message
    Message.create_templated(
      chat: @chat,
      template_type: "browse_results",
      template_data: template_data
    )
  end

  def handle_help_command(user_message)
    template_data = {
      commands: [
        { name: "/search", description: "Search lists" },
        { name: "/browse", description: "Browse lists" },
        { name: "/clear", description: "Clear chat" },
        { name: "/new", description: "New conversation" }
      ],
      features: [
        { symbol: "@name", description: "Mention someone" },
        { symbol: "#list", description: "Reference a list" }
      ]
    }

    Message.create_templated(
      chat: @chat,
      template_type: "help",
      template_data: template_data
    )
  end

  def handle_clear_command
    @chat.messages.destroy_all
    Message.create_system(chat: @chat, content: "Chat history cleared.")
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
      Message.create_templated(
        chat: @chat,
        template_type: "error",
        template_data: {
          message: "I encountered an issue processing your message. Please try again.",
          error_code: "CHAT_ERROR",
          details: result.errors.join(", ")
        }
      )
    end
  end

  def format_search_result(record)
    created_at_str = begin
      record.created_at.strftime("%b %d, %Y")
    rescue
      "Unknown"
    end

    {
      id: record.id,
      type: record.class.name,
      title: extract_search_title(record),
      description: extract_search_description(record),
      url: search_result_url(record),
      created_at: created_at_str
    }
  end

  def extract_search_title(record)
    case record
    when List
      record.title
    when ListItem
      record.title
    when Comment
      "Comment by #{record.user.name}"
    when ActsAsTaggableOn::Tag
      record.name
    else
      "Unknown"
    end
  end

  def extract_search_description(record)
    case record
    when List
      record.description
    when ListItem
      record.description
    when Comment
      record.content
    when ActsAsTaggableOn::Tag
      nil
    else
      nil
    end
  end

  def search_result_url(record)
    case record
    when List
      list_path(record)
    when ListItem
      list_item_path(record.list, record)
    when Comment
      case record.commentable
      when List
        list_path(record.commentable)
      when ListItem
        list_item_path(record.commentable.list, record.commentable)
      else
        root_path
      end
    when ActsAsTaggableOn::Tag
      root_path
    else
      root_path
    end
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
      metadata: {
        template_data: {
          message: text,
          error_code: "CHAT_ERROR"
        }
      }
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
