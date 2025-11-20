# app/controllers/chat/chat_controller.rb
class Chat::ChatController < ApplicationController
  include ListBroadcasting

  before_action :authenticate_user!
  before_action :set_no_cache, only: [ :load_dashboard_history, :create_message ]


  def load_dashboard_history
    Rails.logger.info "=" * 80
    Rails.logger.info "DASHBOARD HISTORY LOAD STARTED"
    Rails.logger.info "=" * 80

    @chat = current_user.chats.where(status: "active")
                              .order(last_message_at: :desc, created_at: :desc)
                              .first

    Rails.logger.info "Chat ID: #{@chat&.id}"

    @messages = if @chat
      msgs = @chat.messages.where(role: [ "user", "assistant" ])
                  .where.not(content: [ nil, "" ])
                  .includes(:user)
                  .order(created_at: :asc)
                  .limit(50)
      Rails.logger.info "Messages count: #{msgs.count}"
      msgs
    else
      Rails.logger.info "No chat - empty array"
      []
    end

    has_messages = @messages.any?
    Rails.logger.info "Has messages: #{has_messages}"

    respond_to do |format|
      format.turbo_stream do
        streams = []

        # Update messages
        streams << turbo_stream.update("dashboard-chat-messages",
          partial: "dashboard/chat_history",
          locals: { messages: @messages }
        )

        # Handle suggestions visibility
        if has_messages
          Rails.logger.info "Showing suggestions bar"
          suggestions_html = render_to_string(
            partial: "dashboard/compact_suggestions",
            formats: [ :html ]
          )

          streams << turbo_stream.replace("dashboard-suggestions-compact",
            html: %(<div id="dashboard-suggestions-compact" class="flex-shrink-0">#{suggestions_html}</div>).html_safe
          )
        else
          Rails.logger.info "Hiding suggestions bar"
          streams << turbo_stream.replace("dashboard-suggestions-compact",
            html: '<div id="dashboard-suggestions-compact" class="hidden flex-shrink-0"></div>'.html_safe
          )
        end

        Rails.logger.info "=" * 80
        render turbo_stream: streams
      end
    end
  end

  def create_message
    Rails.logger.info "=" * 80
    Rails.logger.info "CREATE MESSAGE"
    Rails.logger.info "=" * 80

    message_content = params[:message]
    current_page = params[:current_page]
    context = params[:context] || {}

    from_dashboard = current_page == "dashboard#index"
    target_id = from_dashboard ? "dashboard-chat-messages" : "chat-messages"

    Rails.logger.info "From dashboard: #{from_dashboard}, Target: #{target_id}"

    service = AiAgentMcpService.new(
      user: current_user,
      context: build_chat_context.merge(context.to_unsafe_h)
    )

    result = service.process_message(message_content)

    if result[:lists_created].any?
      result[:lists_created].each do |list|
        broadcast_list_creation(list)
        broadcast_dashboard_updates(list)
      end
    end

    chat = service.chat
    user_message = chat.messages.where(role: "user", content: message_content)
                        .order(created_at: :desc).first
    assistant_message = result[:message]

    Rails.logger.info "User msg: #{user_message&.id}, Assistant: #{assistant_message&.id}"

    message_partial = from_dashboard ? "dashboard/chat_message" : "chat/message"

    respond_to do |format|
      format.turbo_stream do
        streams = []

        if from_dashboard
          total_msgs = chat.messages.where(role: [ "user", "assistant" ]).count

          if total_msgs <= 2
            Rails.logger.info "First message - removing welcome"
            streams << turbo_stream.remove("dashboard-chat-welcome")
          end

          Rails.logger.info "Showing suggestions bar"
          suggestions_html = render_to_string(
            partial: "dashboard/compact_suggestions",
            formats: [ :html ]
          )

          streams << turbo_stream.replace("dashboard-suggestions-compact",
            html: %(<div id="dashboard-suggestions-compact" class="flex-shrink-0">#{suggestions_html}</div>).html_safe
          )
        end

        if user_message
          streams << turbo_stream.append(target_id,
            partial: message_partial,
            locals: { message: user_message, lists_created: [] }
          )
        end

        if assistant_message
          streams << turbo_stream.append(target_id,
            partial: message_partial,
            locals: { message: assistant_message, lists_created: result[:lists_created] }
          )
        end

        Rails.logger.info "Rendering #{streams.count} streams"
        Rails.logger.info "=" * 80

        render turbo_stream: streams
      end
      format.json { render json: result }
    end

  rescue => e
    Rails.logger.error "ERROR: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")

    error_text = Rails.env.development? ? "Error: #{e.message}" : "I encountered an issue. Please try again."

    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.append(target_id,
          partial: "chat/error_message",
          locals: { error_message: error_text }
        )
      end
      format.json { render json: { error: error_text }, status: :unprocessable_entity }
    end
  end

  def load_history
    @chat = current_user.current_chat
    @messages = @chat&.latest_messages_with_includes

    render turbo_stream: turbo_stream.replace("chat-messages",
      partial: "chat/messages_history",
      locals: { messages: @messages || [] }
    )
  end

  private

  def set_no_cache
    response.headers["Cache-Control"] = "no-cache, no-store, must-revalidate"
    response.headers["Pragma"] = "no-cache"
    response.headers["Expires"] = "0"
  end

  def build_chat_context
    {
      page: "#{controller_name}##{action_name}",
      current_page: params[:current_page],
      user_id: current_user.id,
      organization_id: current_organization&.id,
      total_lists: current_user.accessible_lists.count,
      current_time: Time.current.iso8601
    }
  end
end
