# To deliver this notification:
#
# ListTitleChangedNotifier.with(record: @post, message: "New post").deliver(User.all)

# app/notifiers/list_title_changed_notifier.rb
class ListTitleChangedNotifier < ApplicationNotifier
  def notification_type
    "list_activity"
  end

  def title
    "List updated"
  end

  def message
    "#{actor_name} updated \"#{target_list&.title}\""
  end
end
