module ListItemsHelper
  # Format user name for dropdown, adding "(You)" marker for current user
  def format_assignee_name(user)
    if user == current_user
      "#{user.name} (You)"
    else
      user.name
    end
  end

end
