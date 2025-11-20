# app/services/user_filter_service.rb
class UserFilterService
  attr_reader :query, :status, :role, :verified, :sort_by, :organization_id

  def initialize(query: nil, status: nil, role: nil, verified: nil, sort_by: nil, organization_id: nil)
    @query = query&.strip
    @status = status
    @role = role
    @verified = verified
    @sort_by = sort_by || "recent"
    @organization_id = organization_id
  end

  def filtered_users
    users = User.all

    users = apply_organization_filter(users)
    users = apply_search(users)
    users = apply_status_filter(users)
    users = apply_role_filter(users)
    users = apply_verification_filter(users)
    users = apply_sorting(users)

    users
  end

  private

  def apply_organization_filter(users)
    return users if @organization_id.blank?

    users.joins(:organization_memberships)
         .where(organization_memberships: { organization_id: @organization_id })
         .distinct
  end

  def apply_search(users)
    return users if @query.blank?

    escaped_query = escape_search_query(@query)

    users.where(
      "LOWER(users.email) ILIKE ? OR LOWER(users.name) ILIKE ?",
      "%#{escaped_query}%",
      "%#{escaped_query}%"
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

  def escape_search_query(query)
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
