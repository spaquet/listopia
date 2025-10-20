# app/services/user_filter_service.rb
class UserFilterService
  def initialize(query: nil, status: nil, role: nil, verified: nil, sort_by: nil)
    @query = query&.strip
    @status = status
    @role = role
    @verified = verified
    @sort_by = sort_by || "recent"
  end

  def filtered_users
    users = User.all

    # Search by name or email
    users = search_users(users) if @query.present?

    # Filter by status
    users = users.where(status: @status) if @status.present? && valid_status?

    # Filter by role (admin)
    if @role.present? && valid_role?
      if @role == "admin"
        users = users.with_role(:admin)
      elsif @role == "user"
        users = users.without_role(:admin)
      end
    end

    # Filter by email verification status
    if @verified.present? && valid_verified?
      if @verified == "verified"
        users = users.where.not(email_verified_at: nil)
      elsif @verified == "unverified"
        users = users.where(email_verified_at: nil)
      end
    end

    # Apply sorting
    apply_sorting(users)
  end

  private

  def search_users(users)
    search_term = "%#{@query}%"
    users.where("name ILIKE ? OR email ILIKE ?", search_term, search_term)
  end

  def apply_sorting(users)
    case @sort_by
    when "name_asc"
      users.order(name: :asc)
    when "name_desc"
      users.order(name: :desc)
    when "email_asc"
      users.order(email: :asc)
    when "email_desc"
      users.order(email: :desc)
    when "oldest"
      users.order(created_at: :asc)
    else # 'recent' is default
      users.order(created_at: :desc)
    end
  end

  def valid_status?
    [ "active", "suspended", "inactive" ].include?(@status)
  end

  def valid_role?
    [ "admin", "user" ].include?(@role)
  end

  def valid_verified?
    [ "verified", "unverified" ].include?(@verified)
  end
end
