# app/controllers/chat_controller.rb
class ChatController < ApplicationController
  before_action :authenticate_user!

  def create_message
    message = chat_params[:message]
    context = chat_params[:context] || {}
    current_page = chat_params[:current_page]

    # Log the context for debugging (remove in production)
    Rails.logger.info "Chat Context: #{context.inspect}"
    Rails.logger.info "Current Page: #{current_page}"

    # Generate contextual response
    response_message = generate_contextual_response(message, context, current_page)

    respond_with_turbo_stream do |format|
      format.turbo_stream do
        render turbo_stream: turbo_stream.append(
          "chat-messages",
          partial: "chat/assistant_message",
          locals: { message: response_message }
        )
      end
    end
  end

  private

  def chat_params
    params.permit(:message, :current_page, context: {})
  end

  def generate_contextual_response(user_message, context, current_page)
    # Use context to provide more relevant responses
    case current_page
    when "lists#show"
      generate_list_show_response(user_message, context)
    when "lists#index"
      generate_list_index_response(user_message, context)
    when "analytics#index"
      generate_analytics_response(user_message, context)
    when "dashboard#index"
      generate_dashboard_response(user_message, context)
    else
      generate_default_response(user_message, context)
    end
  end

  def generate_list_show_response(message, context)
    list_title = context["list_title"] || "this list"

    case message.downcase
    when /add.*item|create.*item/
      "I can see you're viewing '#{list_title}'. Once I'm connected to the MCP system, I'll be able to add items directly to this list. For now, you can use the form below to add items manually."
    when /share.*list|collaborate/
      "Great! I can help you share '#{list_title}' with others. Once the MCP integration is ready, I'll be able to send invitations directly. Currently, you can use the share button in the list header."
    when /complete|finish|done/
      if context["items_count"].to_i > 0
        "I can see '#{list_title}' has #{context['items_count']} items with #{context['completed_count']} completed. I'll soon be able to help you mark items as complete right from this chat!"
      else
        "This list doesn't have any items yet. Would you like me to help you add some items when my MCP integration is ready?"
      end
    when /analyze|progress|how.*doing/
      "#{list_title} currently has #{context['completed_count']}/#{context['items_count']} items completed. Once I'm fully integrated, I'll provide detailed progress insights and suggestions!"
    else
      "I can see you're working on '#{list_title}'. I'll soon be able to help you add items, mark them complete, share the list, and much more. What would you like to do with this list?"
    end
  end

  def generate_list_index_response(message, context)
    total_lists = context["total_lists"] || 0

    case message.downcase
    when /create.*list|new.*list|make.*list/
      "I can see you have #{total_lists} lists already! Once my MCP integration is complete, I'll be able to create new lists instantly. What kind of list would you like to create?"
    when /show.*lists|my.*lists/
      "You currently have #{total_lists} accessible lists. I'll soon be able to show you summaries, filter them, and help you organize them better!"
    else
      "I can see your lists overview with #{total_lists} total lists. Soon I'll help you create, organize, and manage all your lists through natural conversation!"
    end
  end

  def generate_analytics_response(message, context)
    list_title = context["list_title"] || "this list"

    "I can see you're viewing analytics for '#{list_title}'. Once my MCP integration is ready, I'll be able to explain these metrics, provide insights, and suggest improvements based on the data shown!"
  end

  def generate_dashboard_response(message, context)
    overdue_items = context["overdue_items"] || 0

    if overdue_items > 0
      "I can see from your dashboard that you have #{overdue_items} overdue items. Once I'm fully integrated, I'll help you prioritize and tackle these items efficiently!"
    else
      "Your dashboard shows you're staying on top of things! I'll soon be able to help you plan your day, create new lists, and provide productivity insights."
    end
  end

  def generate_default_response(message, context)
    current_page = context["page"] || "this page"

    case message.downcase
    when /create.*list|new.*list/
      "I'd love to help you create a list! I can see you're on #{current_page}. Once I'm connected to the MCP system, I'll be able to create lists with items automatically."
    when /help|what can you do/
      "I'm your Listopia assistant! I can see the context of where you are (#{current_page}) and will soon be able to provide contextual help based on what you're viewing. Full MCP integration coming soon!"
    else
      "I understand you want to work with '#{message}' while viewing #{current_page}. My contextual awareness is ready, and MCP integration will make me much more helpful soon!"
    end
  end
end
