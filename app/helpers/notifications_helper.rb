# app/helpers/notifications_helper.rb
module NotificationsHelper
  # Get color class for notification based on type
  def notification_color(notification)
    case notification.notification_type
    when "collaboration"
      "blue"
    when "list_status", "status_change"
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
    when "item_assignment"
      "purple"
    when "item_comment"
      "cyan"
    when "item_completion"
      "green"
    when "item_priority_changed"
      "orange"
    when "permission_changed"
      "indigo"
    when "team_invitation"
      "pink"
    when "list_archived"
      "slate"
    when "mention"
      "amber"
    when "digest"
      "blue"
    else
      "gray"
    end
  end

  # Get notification type badge
  def notification_type_badge(notification)
    type_config = {
      "collaboration" => { text: "Collaboration", color: "blue" },
      "list_status" => { text: "List Status", color: "purple" },
      "status_change" => { text: "Status Change", color: "purple" },
      "item_activity" => { text: "Item Activity", color: "green" },
      "item_assignment" => { text: "Assignment", color: "purple" },
      "item_comment" => { text: "Comment", color: "cyan" },
      "item_completion" => { text: "Completed", color: "green" },
      "item_priority_changed" => { text: "Priority", color: "orange" },
      "permission_changed" => { text: "Permission", color: "indigo" },
      "team_invitation" => { text: "Team Invite", color: "pink" },
      "list_archived" => { text: "List Archived", color: "slate" },
      "mention" => { text: "Mention", color: "amber" },
      "digest" => { text: "Digest", color: "blue" }
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

  # Extract and highlight mentions in text
  # Returns HTML-safe string with mentions highlighted and linked
  def highlight_mentions(text)
    return text unless text.present?

    # Replace @username with highlighted mention links
    highlighted = text.gsub(/@(\w+)/) do |match|
      handle = $1
      user = User.where("email ILIKE ? OR CONCAT(first_name, ' ', last_name) ILIKE ?", "%#{handle}%", "%#{handle}%").first

      if user
        content_tag :span, match,
                    class: "font-semibold text-blue-600 bg-blue-50 px-1 rounded",
                    title: user.name,
                    data: { user_id: user.id }
      else
        match
      end
    end

    highlighted.html_safe
  end

  # Extract mentioned usernames from text
  def extract_mentioned_usernames(text)
    return [] unless text.present?

    matches = text.scan(/@(\w+)/)
    matches.flatten.uniq
  end

  # Get notification context details for display
  def notification_context(notification)
    context = {
      actor: notification.actor&.name || "Someone",
      type: notification.notification_type,
      created_at: notification.created_at,
      title: notification.title,
      message: notification.message
    }

    # Add type-specific context
    case notification.notification_type
    when "item_assignment", "item_completion", "item_comment"
      context[:item_title] = notification.event.params[:item_title]
      context[:list_title] = notification.target_list&.title
      context[:list_url] = list_path(notification.target_list) if notification.target_list
    when "item_priority_changed"
      context[:item_title] = notification.event.params[:item_title]
      context[:new_priority] = notification.event.params[:new_priority]&.humanize
      context[:list_title] = notification.target_list&.title
    when "permission_changed"
      context[:list_title] = notification.target_list&.title
      context[:new_permission] = notification.event.params[:new_permission]
    when "status_change"
      context[:list_title] = notification.target_list&.title
      context[:previous_status] = notification.previous_status&.humanize
      context[:new_status] = notification.new_status&.humanize
    when "list_archived"
      context[:list_title] = notification.event.params[:list_title]
    when "team_invitation"
      context[:team_name] = notification.event.params[:team_name]
    when "mention"
      context[:comment_preview] = notification.event.params[:comment_preview]
      context[:commentable_title] = notification.event.params[:commentable_title]
    when "digest"
      context[:frequency] = notification.event.params[:frequency]
      context[:item_count] = notification.event.params[:item_count] || 0
      context[:comment_count] = notification.event.params[:comment_count] || 0
      context[:status_count] = notification.event.params[:status_count] || 0
    end

    context
  end

  # Format notification context for display
  def format_notification_context(notification)
    context = notification_context(notification)

    case notification.notification_type
    when "item_assignment"
      "#{context[:actor]} assigned you \"#{context[:item_title]}\" on #{context[:list_title]}"
    when "item_comment"
      "#{context[:actor]} commented on \"#{context[:item_title]}\" on #{context[:list_title]}"
    when "item_completion"
      "#{context[:actor]} completed \"#{context[:item_title]}\" on #{context[:list_title]}"
    when "item_priority_changed"
      "#{context[:actor]} changed priority to #{context[:new_priority]} for \"#{context[:item_title]}\""
    when "permission_changed"
      "#{context[:actor]} changed your permission to #{context[:new_permission]} on #{context[:list_title]}"
    when "status_change"
      "#{context[:list_title]} status changed from #{context[:previous_status]} to #{context[:new_status]}"
    when "list_archived"
      "#{context[:actor]} archived \"#{context[:list_title]}\""
    when "team_invitation"
      "#{context[:actor]} invited you to #{context[:team_name]}"
    when "mention"
      "#{context[:actor]} mentioned you on #{context[:commentable_title]}"
    when "digest"
      "#{context[:frequency].capitalize} digest: #{context[:item_count]} items, #{context[:comment_count]} comments"
    else
      context[:message]
    end
  end

  # Get icon name for notification type
  def notification_icon_name(notification)
    case notification.notification_type
    when "item_assignment"
      "clipboard-list"
    when "item_comment"
      "message-square"
    when "item_completion"
      "check-circle"
    when "item_priority_changed"
      "alert-circle"
    when "permission_changed"
      "lock"
    when "team_invitation"
      "users"
    when "list_archived"
      "archive"
    when "mention"
      "at-sign"
    when "digest"
      "inbox"
    else
      "bell"
    end
  end
end
