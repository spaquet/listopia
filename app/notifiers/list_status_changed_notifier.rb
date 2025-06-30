# To deliver this notification:
#
# ListStatusChangedNotifier.with(record: @post, message: "New post").deliver(User.all)

# app/notifiers/list_status_changed_notifier.rb
class ListStatusChangedNotifier < ApplicationNotifier
  def notification_type
    "status_change"
  end

  def title
    "List status changed"
  end

  def message
    "#{actor_name} changed list status to #{params[:new_status]}"
  end
end
