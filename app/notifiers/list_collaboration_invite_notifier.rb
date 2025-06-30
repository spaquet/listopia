# To deliver this notification:
#
# ListCollaborationInviteNotifier.with(record: @post, message: "New post").deliver(User.all)

# app/notifiers/list_collaboration_invite_notifier.rb
class ListCollaborationInviteNotifier < ApplicationNotifier
  def notification_type
    "collaboration"
  end

  def title
    "Collaboration invitation"
  end

  def message
    "#{actor_name} invited you to collaborate on \"#{target_list&.title}\""
  end
end
