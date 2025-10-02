# app/helpers/lists_helper.rb
module ListsHelper
  # Include ItemTypesHelper to get access to item_type_icon_svg
  include ItemTypesHelper

  # Calculate list completion statistics
  def list_completion_stats(list)
    total = list.list_items.count
    completed = list.list_items.where(status: 2).count
    percentage = total.zero? ? 0 : ((completed.to_f / total) * 100).round

    {
      total: total,
      completed: completed,
      pending: total - completed,
      percentage: percentage
    }
  end

  # Render progress bar
  def progress_bar(percentage)
    content_tag :div, class: "w-full bg-gray-200 rounded-full h-2" do
      content_tag :div, "",
        class: "bg-blue-500 h-2 rounded-full transition-all duration-300",
        style: "width: #{percentage}%"
    end
  end

  # Display list status badge
  def list_status_badge(list)
    colors = {
      "draft" => "bg-gray-100 text-gray-800",
      "active" => "bg-green-100 text-green-800",
      "completed" => "bg-blue-100 text-blue-800",
      "archived" => "bg-yellow-100 text-yellow-800"
    }

    content_tag :span, list.status.titleize,
      class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{colors[list.status]}"
  end

  # Display list sharing status
  def list_sharing_status(list)
    if list.is_public?
      content_tag :span, class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800" do
        concat content_tag(:span, "🌐", class: "mr-1")
        concat "Public"
      end
    elsif list.collaborators.any?
      content_tag :span, class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800" do
        concat content_tag(:span, "👥", class: "mr-1")
        concat "Shared with #{list.collaborators.count}"
      end
    else
      content_tag :span, class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800" do
        concat content_tag(:span, "🔒", class: "mr-1")
        concat "Private"
      end
    end
  end

  # Get user's permission level for a list
  def list_permission_for_user(list, user)
    return :none unless user
    return :owner if list.owner == user

    # Check if it's a public list
    if list.is_public?
      return :public_write if list.respond_to?(:public_permission_public_write?) && list.public_permission_public_write?
      return :public_read
    end

    # Check collaborator permission
    collaborator = list.collaborators.find_by(user: user)
    return :none unless collaborator

    # Return the permission symbol
    collaborator.permission.to_sym
  end

  # Check if user can edit list
  def can_edit_list?(list, user)
    permission = list_permission_for_user(list, user)
    [ :owner, :write, :public_write ].include?(permission)
  end

  # Check if user can share list
  def can_share_list?(list, user)
    permission = list_permission_for_user(list, user)
    [ :owner, :write ].include?(permission)
  end

  # Check if user can delete list
  def can_delete_list?(list, user)
    list.owner == user
  end

  # Check if user can view list
  def can_view_list?(list, user)
    permission = list_permission_for_user(list, user)
    [ :owner, :write, :read, :public_write, :public_read ].include?(permission)
  end

  # Get available actions for user
  def available_list_actions(list, user)
    actions = []
    actions << :edit if can_edit_list?(list, user)
    actions << :share if can_share_list?(list, user)
    actions << :duplicate if can_view_list?(list, user)
    actions << :delete if can_delete_list?(list, user)
    actions
  end

  # General access check (backward compatible)
  def can_access_list?(list, user, permission = :read)
    return can_view_list?(list, user) if permission == :read
    return can_edit_list?(list, user) if permission == :edit
    can_view_list?(list, user)
  end

  # Check if user can duplicate list
  def can_duplicate_list?(list, user)
    can_view_list?(list, user)
  end

  # Display list type icon
  def list_type_icon(list_type)
    icons = {
      "professional" => "💼",
      "personal" => "🏠",
      "shared" => "👥"
    }

    content_tag :span, icons[list_type] || "📝", class: "text-lg"
  end

  # Get sharing permission options for forms
  def sharing_permission_options
    [
      [ "Read Only", "read" ],
      [ "Read & Write", "write" ]
    ]
  end

  # Check if list has collaborators
  def list_has_collaborators?(list)
    list.collaborators.any?
  end

  # Generate item type icon - delegates to ItemTypesHelper
  def item_type_icon(item_type)
    item_type_icon_svg(item_type, css_class: "w-4 h-4")
  end
end
