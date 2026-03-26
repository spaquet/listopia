# Event subscription setup
# This file registers subscribers for app events
# New subscriptions can be added here following the pattern below

# AI Agent event triggers
# When a list item is completed, dispatch to agents listening for list_item.completed
ActiveSupport::Notifications.subscribe("list_item.completed") do |_name, _start, _finish, _id, payload|
  item = payload[:item]
  event_payload = {
    item: item.slice(:id, :title, :description, :status),
    item_id: item.id,
    list_id: item.list_id,
    organization_id: item.list.organization_id
  }
  AgentEventDispatchJob.perform_later("list_item.completed", event_payload)
end

# When a list item is created, dispatch to agents listening for list_item.created
ActiveSupport::Notifications.subscribe("list_item.created") do |_name, _start, _finish, _id, payload|
  item = payload[:item]
  event_payload = {
    item: item.slice(:id, :title, :description, :status),
    item_id: item.id,
    list_id: item.list_id,
    organization_id: item.list.organization_id
  }
  AgentEventDispatchJob.perform_later("list_item.created", event_payload)
end

# When a list item is updated, dispatch to agents listening for list_item.updated
ActiveSupport::Notifications.subscribe("list_item.updated") do |_name, _start, _finish, _id, payload|
  item = payload[:item]
  event_payload = {
    item: item.slice(:id, :title, :description, :status),
    item_id: item.id,
    list_id: item.list_id,
    organization_id: item.list.organization_id
  }
  AgentEventDispatchJob.perform_later("list_item.updated", event_payload)
end

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
