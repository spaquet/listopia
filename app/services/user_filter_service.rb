# app/services/user_filter_service.rb
class UserFilterService
  attr_reader :query, :status, :role, :verified, :sort_by

  def initialize(query: nil, status: nil, role: nil, verified: nil, sort_by: nil)
    @query = query&.strip
    @status = status
    @role = role
    @verified = verified
    @sort_by = sort_by || "recent"
  end

  def filtered_users
    users = User.all

    # Apply filters in order
    users = apply_search(users)
    users = apply_status_filter(users)
    users = apply_role_filter(users)
    users = apply_verification_filter(users)
    users = apply_sorting(users)

    users
  end

  private

  def apply_search(users)
    return users if @query.blank?

    # Use PgSearch for better full-text search performance
    users.where(
      "LOWER(users.name) ILIKE ? OR LOWER(users.email) ILIKE ? OR users.id::text ILIKE ?",
      "%#{sanitize_query(@query)}%",
      "%#{sanitize_query(@query)}%",
      "%#{sanitize_query(@query)}%"
    )
  end

  def apply_status_filter(users)
    return users if @status.blank? || !valid_status?(@status)

    users.where(status: @status)
  end

  def apply_role_filter(users)
    return users if @role.blank? || !valid_role?(@role)

    case @role
    when "admin"
      users.with_role(:admin)
    when "user"
      users.without_role(:admin)
    else
      users
    end
  end

  def apply_verification_filter(users)
    return users if @verified.blank? || !valid_verified?(@verified)

    case @verified
    when "verified"
      users.where.not(email_verified_at: nil)
    when "unverified"
      users.where(email_verified_at: nil)
    else
      users
    end
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
    else
      users.order(created_at: :desc)
    end
  end

  def sanitize_query(query)
    # Remove SQL injection attempts and special characters
    query.gsub(/[%_\\]/, '\\\\\0')
  end

  def valid_status?(status)
    %w[active suspended inactive].include?(status)
  end

  def valid_role?(role)
    %w[admin user].include?(role)
  end

  def valid_verified?(verified)
    %w[verified unverified].include?(verified)
  end
end
