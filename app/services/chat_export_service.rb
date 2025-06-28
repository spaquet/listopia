class ChatExportService
  def initialize(chat, user)
    @chat = chat
    @user = user
  end

  def export_to_text
    output = []
    output << "=" * 80
    output << "LISTOPIA CHAT EXPORT"
    output << "=" * 80
    output << ""
    output << "Chat ID: #{@chat.id}"
    output << "User: #{@user.name} (#{@user.email})"
    output << "Created: #{@chat.created_at.strftime('%Y-%m-%d %H:%M:%S %Z')}"
    output << "Last Message: #{@chat.last_message_at&.strftime('%Y-%m-%d %H:%M:%S %Z') || 'N/A'}"
    output << "Total Messages: #{@chat.messages.count}"
    output << ""
    output << "=" * 80
    output << "CONVERSATION HISTORY"
    output << "=" * 80
    output << ""

    messages = @chat.messages.order(:created_at)

    if messages.empty?
      output << "(No messages in this chat)"
    else
      messages.each_with_index do |message, index|
        output << format_message(message, index + 1)
        output << ""
      end
    end

    output << "=" * 80
    output << "END OF CHAT EXPORT"
    output << "=" * 80

    output.join("\n")
  end

  private

  def format_message(message, sequence_number)
    lines = []

    timestamp = message.created_at.strftime("%Y-%m-%d %H:%M:%S")
    sender = format_sender(message)

    lines << "#{sequence_number}. [#{timestamp}] #{sender}"
    lines << "-" * 40

    if message.content.present?
      lines << "Content:"
      lines << message.content.strip
    else
      lines << "Content: (empty)"
    end

    if message.tool_calls.any?
      lines << ""
      lines << "Tool Calls:"
      message.tool_calls.each do |tool_call|
        lines << "  - #{tool_call.name} (ID: #{tool_call.tool_call_id})"
        lines << "    Arguments: #{tool_call.arguments.to_json}" if tool_call.arguments.present?
      end
    end

    lines.join("\n")
  end

  def format_sender(message)
    case message.role
    when "user"
      "USER (#{@user.name})"
    when "assistant"
      "AI ASSISTANT"
    when "system"
      "SYSTEM"
    when "tool"
      "TOOL RESPONSE"
    else
      "UNKNOWN (#{message.role})"
    end
  end
end
