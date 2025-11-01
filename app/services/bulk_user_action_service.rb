# app/services/bulk_user_action_service.rb
class BulkUserActionService
  attr_reader :message, :error_message

  def initialize(current_user, user_ids, action)
    @current_user = current_user
    @user_ids = user_ids
    @action = action
    @processed_count = 0
    @failed_count = 0
    @message = nil
    @error_message = nil
  end

  def execute
    return error("Invalid action") unless valid_action?
    return error("No users selected") if @user_ids.empty?

    users = User.where(id: @user_ids).where.not(id: @current_user.id)

    return error("No valid users to process") if users.empty?

    begin
      case @action
      when "suspend"
        suspend_users(users)
      when "activate"
        activate_users(users)
      when "make_admin"
        make_admin_users(users)
      when "remove_admin"
        remove_admin_users(users)
      when "delete"
        delete_users(users)
      end

      @message = generate_success_message
      true
    rescue StandardError => e
      error("Failed to process action: #{e.message}")
    end
  end

  private

  def suspend_users(users)
    users.each do |user|
      user.suspend!(reason: "Bulk action by admin", suspended_by: @current_user)
      @processed_count += 1
    end
  end

  def activate_users(users)
    suspended_users = users.where(status: "suspended")
    suspended_users.each do |user|
      user.unsuspend!(unsuspended_by: @current_user)
      @processed_count += 1
    end
  end

  def make_admin_users(users)
    non_admin_users = users.without_role(:admin)
    non_admin_users.each do |user|
      user.add_role(:admin)
      @processed_count += 1
    end
  end

  def remove_admin_users(users)
    admin_users = users.with_role(:admin)
    admin_users.each do |user|
      user.remove_role(:admin)
      @processed_count += 1
    end
  end

  def delete_users(users)
    users.each do |user|
      if user.destroy
        @processed_count += 1
      else
        @failed_count += 1
      end
    end
  end

  def generate_success_message
    case @action
    when "suspend"
      "#{@processed_count} user(s) suspended successfully."
    when "activate"
      "#{@processed_count} user(s) activated successfully."
    when "make_admin"
      "#{@processed_count} user(s) promoted to admin."
    when "remove_admin"
      "#{@processed_count} user(s) demoted from admin."
    when "delete"
      "#{@processed_count} user(s) deleted successfully." + (@failed_count > 0 ? " #{@failed_count} failed." : "")
    end
  end

  def valid_action?
    [ "suspend", "activate", "make_admin", "remove_admin", "delete" ].include?(@action)
  end

  def error(message)
    @error_message = message
    false
  end
end
