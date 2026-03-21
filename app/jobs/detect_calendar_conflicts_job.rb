class DetectCalendarConflictsJob < ApplicationJob
  queue_as :default

  def perform(user_id:, organization_id:)
    user = User.find(user_id)
    organization = Organization.find(organization_id)

    result = Connectors::Calendars::CalendarConflictScanService.new(
      user: user, organization: organization
    ).call
    return unless result.success? && result.data.any?

    conflicts = result.data

    # 1. Broadcast conflict card to most recent active chat
    recent_chat = Chat.where(user_id: user.id, organization_id: organization.id)
                      .where.not(status: "archived")
                      .order(updated_at: :desc)
                      .first
    if recent_chat
      Turbo::StreamsChannel.broadcast_append_to(
        "chat_#{recent_chat.id}",
        target: "chat-messages-#{recent_chat.id}",
        html: ApplicationController.render(
          partial: "chats/calendar_conflict_alert",
          locals: { conflicts: conflicts, user: user }
        )
      )
    end

    # 2. Send Noticed notification (shows in notification bell regardless of chat)
    CalendarConflictNotifier.with(
      user_id: user.id,
      conflict_count: conflicts.size,
      first_conflict_summary: conflicts.first[:event].summary
    ).deliver([ user ])
  rescue ActiveRecord::RecordNotFound
    # User or org deleted
  end
end
