# app/helpers/lists_helper.rb
module ListsHelper
  # Calculate and display list completion statistics
  def list_completion_stats(list)
    total = list.list_items_count
    completed = list.list_items.completed.count
    percentage = total > 0 ? (completed.to_f / total * 100).round : 0

    {
      total: total,
      completed: completed,
      pending: total - completed,
      percentage: percentage
    }
  end

  # Add efficient collaboration check
  def list_has_collaborators?(list)
    list.collaborators.any?
  end

  # Generate sharing permissions options for select
  def sharing_permission_options
    [
      [ "Read Only", "read" ],
      [ "Read & Write", "write" ]
    ]
  end

  # Format list sharing status
  def list_sharing_status(list)
    if list.is_public?
      content_tag :span, "Public",
                  class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-green-100 text-green-800 ml-2"
    elsif list.collaborators.any?
      collaborator_count = list.collaborators.count
      content_tag :span, "#{collaborator_count} #{'collaborator'.pluralize(collaborator_count)}",
                  class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-blue-100 text-blue-800 ml-2"
    else
      content_tag :span, "Private",
                  class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800 ml-2"
    end
  end

  # New helper methods for permission-based actions
  def list_permission_for_user(list, user)
    return :none unless user
    return :owner if list.owner == user

    # Check if it's a public list
    if list.is_public?
      return :public_write if list.public_permission_public_write?
      return :public_read
    end

    # Check collaborator permission using the correct association
    collaborator = list.collaborators.find_by(user: user)
    return :none unless collaborator

    # Return the actual permission symbol from the enum
    # Debug: let's see what we get
    Rails.logger.debug "Collaborator found: #{collaborator.inspect}"
    Rails.logger.debug "Permission: #{collaborator.permission}"
    Rails.logger.debug "Permission symbol: #{collaborator.permission.to_sym}"

    collaborator.permission.to_sym  # This will return :read or :write
  end

  # Check if user can edit a list (edit action)
  def can_edit_list?(list, user)
    permission = list_permission_for_user(list, user)
    result = [:owner, :write, :public_write].include?(permission)
    Rails.logger.debug "can_edit_list? permission=#{permission}, result=#{result}"
    result
  end

  # Check if user can share a list (share action)
  def can_share_list?(list, user)
    permission = list_permission_for_user(list, user)
    result = [:owner, :write].include?(permission)
    Rails.logger.debug "can_share_list? permission=#{permission}, result=#{result}"
    result
  end

  # Check if user can delete a list (delete action)
  def can_delete_list?(list, user)
    # Only owner can delete
    result = list.owner == user
    Rails.logger.debug "can_delete_list? owner=#{list.owner == user}, result=#{result}"
    result
  end

  # Check if user can view a list
  def can_view_list?(list, user)
    permission = list_permission_for_user(list, user)
    [:owner, :write, :read, :public_write, :public_read].include?(permission)
  end

  # Helper to get available actions for current user
  def available_list_actions(list, user)
    actions = []

    actions << :edit if can_edit_list?(list, user)
    actions << :share if can_share_list?(list, user)
    actions << :delete if can_delete_list?(list, user)

    actions
  end

  # For backward compatibility - this method was referenced in your current code
  def can_access_list?(list = @list, user = current_user, permission = :read)
    return can_view_list?(list, user) if permission == :read
    return can_edit_list?(list, user) if permission == :edit

    # Default to view permission
    can_view_list?(list, user)
  end

  # Generate item type icon - delegates to ItemTypesHelper for DRY code
  def item_type_icon(item_type)
    item_type_icon_svg(item_type, css_class: "w-4 h-4")
  end
end
