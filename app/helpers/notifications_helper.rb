# app/helpers/notifications_helper.rb
module NotificationsHelper
  # Get color class for notification based on type
  def notification_color(notification)
    case notification.notification_type
    when "collaboration"
      "blue"
    when "list_status"
      case notification.new_status
      when "completed"
        "green"
      when "archived"
        "yellow"
      when "active"
        "blue"
      else
        "gray"
      end
    when "item_activity"
      case notification.action_type
      when "created"
        "green"
      when "completed"
        "emerald"
      when "deleted"
        "red"
      when "updated"
        "blue"
      else
        "gray"
      end
    else
      "gray"
    end
  end

  # Get notification type badge
  def notification_type_badge(notification)
    type_config = {
      "collaboration" => { text: "Collaboration", color: "blue" },
      "list_status" => { text: "List Status", color: "purple" },
      "item_activity" => { text: "Item Activity", color: "green" }
    }

    config = type_config[notification.notification_type] || { text: "Notification", color: "gray" }

    content_tag :span, config[:text],
                class: "inline-flex items-center px-2 py-0.5 rounded-full text-xs font-medium bg-#{config[:color]}-100 text-#{config[:color]}-800"
  end

  # Format notification time
  def notification_time(notification)
    if notification.created_at > 1.day.ago
      "#{time_ago_in_words(notification.created_at)} ago"
    else
      notification.created_at.strftime("%b %d, %Y at %I:%M %p")
    end
  end

  # Get notification summary for current user
  def notification_summary(user)
    {
      total: user.notifications.count,
      unread: user.notifications.unread.count,
      unseen: user.notifications.unseen.count,
      today: user.notifications.where(created_at: Date.current.all_day).count
    }
  end
end
