# Base class for event subscribers
# Integrations can inherit from this to subscribe to app events
#
# Example:
#   class SlackIntegration < EventSubscriber
#     def initialize
#       super
#       subscribe_to("list_item.completed") { |payload| notify_slack(payload) }
#     end
#
#     private
#
#     def notify_slack(payload)
#       item = payload[:item]
#       # Send notification to Slack
#     end
#   end

class EventSubscriber
  def initialize
    @subscriptions = []
  end

  protected

  def subscribe_to(event_name, &block)
    ActiveSupport::Notifications.subscribe(event_name) do |name, start, finish, id, payload|
      block.call(payload)
    end
    @subscriptions << event_name
  end
end
