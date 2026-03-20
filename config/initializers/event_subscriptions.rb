# Event subscription setup
# This file registers subscribers for app events
# New subscriptions can be added here following the pattern below

# Example: Subscribe to list item completion for integration notifications
# ActiveSupport::Notifications.subscribe("list_item.completed") do |name, start, finish, id, payload|
#   item = payload[:item]
#   SlackNotifier.notify_item_completed(item)
# end

# Example: Subscribe to list item creation for calendar sync
# ActiveSupport::Notifications.subscribe("list_item.created") do |name, start, finish, id, payload|
#   item = payload[:item]
#   CalendarSync.enqueue_item_sync(item)
# end
