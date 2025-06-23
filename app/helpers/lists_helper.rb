# app/helpers/lists_helper.rb
module ListsHelper
  # Calculate and display list completion statistics
  def list_completion_stats(list)
    total = list.list_items.count
    completed = list.list_items.completed.count
    percentage = total > 0 ? (completed.to_f / total * 100).round : 0

    {
      total: total,
      completed: completed,
      pending: total - completed,
      percentage: percentage
    }
  end

  # Generate sharing permissions options for select
  def sharing_permission_options
    [
      [ "Can view only", "read" ],
      [ "Can edit and add items", "collaborate" ]
    ]
  end

  # Format list sharing status
  def list_sharing_status(list)
    if list.is_public?
      content_tag :span, "Public", class: "text-green-600 font-medium"
    elsif list.list_collaborations.any?
      count = list.list_collaborations.count
      content_tag :span, "Shared with #{count} #{'person'.pluralize(count)}", class: "text-blue-600"
    else
      content_tag :span, "Private", class: "text-gray-600"
    end
  end

  # Generate item type icon
  def item_type_icon(item_type)
    icons = {
      "task" => "✓",
      "note" => "📝",
      "link" => "🔗",
      "file" => "📎",
      "reminder" => "⏰"
    }

    content_tag :span, icons[item_type] || "•", class: "mr-2"
  end

  # Check if list is accessible by current user
  def can_access_list?(list, user, permission = :read)
    return false unless user && list

    case permission
    when :read
      list.readable_by?(user)
    when :edit
      list.collaboratable_by?(user)
    else
      false
    end
  end
end
