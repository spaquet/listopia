# To deliver this notification:
#
# ListItemActivityNotifier.with(record: @post, message: "New post").deliver(User.all)

# app/notifiers/list_item_activity_notifier.rb
class ListItemActivityNotifier < ApplicationNotifier
  def notification_type
    "item_activity"
  end

  def title
    "Item #{params[:action]}"
  end

  def message
    "#{actor_name} #{params[:action]} \"#{params[:item_title]}\""
  end
end
