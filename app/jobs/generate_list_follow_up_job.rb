class GenerateListFollowUpJob < ApplicationJob
  queue_as :default

  def perform(list_id, chat_id)
    list = List.find_by(id: list_id)
    chat = Chat.find_by(id: chat_id)
    return unless list && chat

    result = ListFollowUpService.call(
      list: list,
      user: chat.user,
      organization: chat.organization
    )
    return unless result.success?

    options = result.data
    return if options.values.all?(&:empty?)

    msg = Message.create_templated(
      chat: chat,
      template_type: "list_followup",
      template_data: {
        list_id: list.id,
        list_title: list.title,
        chat_id: chat.id,
        questions: options[:questions],
        suggestions: options[:suggestions],
        actions: options[:actions]
      }
    )

    Turbo::StreamsChannel.broadcast_append_to(
      "chat_#{chat.id}",
      target: "chat-messages-#{chat.id}",
      html: ApplicationController.render(
        partial: "chats/assistant_message_replacement",
        locals: { message: msg, chat_context: chat.build_ui_context }
      )
    )

    Rails.logger.debug("Follow-up options broadcast for list #{list_id}")
  rescue => e
    Rails.logger.error("GenerateListFollowUpJob failed: #{e.class} - #{e.message}")
  end
end
