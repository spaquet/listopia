# app/controllers/chat/exports_controller.rb
class Chat::ExportsController < ApplicationController
  before_action :authenticate_user!

  def show
    chat = current_user.current_chat
    return redirect_to root_path, alert: "No active chat found." unless chat

    export_service = ChatExportService.new(chat, current_user)
    content = export_service.export_to_text
    filename = "listopia_chat_#{chat.id}_#{Date.current.strftime('%Y%m%d')}.txt"

    send_data content,
              filename: filename,
              type: "text/plain",
              disposition: "attachment"
  end
end
