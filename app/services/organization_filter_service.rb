# app/services/organization_filter_service.rb
class OrganizationFilterService
  attr_reader :query, :status, :size, :sort_by

  def initialize(query: nil, status: nil, size: nil, sort_by: nil, base_scope: nil)
    @query = query&.strip
    @status = status
    @size = size
    @sort_by = sort_by || "recent"
    @base_scope = base_scope || Organization.all
  end

  def filtered_organizations
    organizations = @base_scope

    organizations = apply_search(organizations)
    organizations = apply_status_filter(organizations)
    organizations = apply_size_filter(organizations)
    organizations = apply_sorting(organizations)

    organizations
  end

  private

  def apply_search(organizations)
    return organizations if @query.blank?

    escaped_query = escape_search_query(@query)

    organizations.where(
      "LOWER(organizations.name) ILIKE ? OR LOWER(organizations.slug) ILIKE ?",
      "%#{escaped_query}%",
      "%#{escaped_query}%"
    )
  end

  def apply_status_filter(organizations)
    return organizations if @status.blank? || !valid_status?(@status)

    organizations.where(status: @status)
  end

  def apply_size_filter(organizations)
    return organizations if @size.blank? || !valid_size?(@size)

    organizations.where(size: @size)
  end

  def apply_sorting(organizations)
    case @sort_by
    when "name_asc"
      organizations.order(name: :asc)
    when "name_desc"
      organizations.order(name: :desc)
    when "size_large"
      organizations.order(size: :desc)
    when "size_small"
      organizations.order(size: :asc)
    when "oldest"
      organizations.order(created_at: :asc)
    else
      organizations.order(created_at: :desc)
    end
  end

  def escape_search_query(query)
    query.gsub(/[%_\\]/, '\\\\\0')
  end

  def valid_status?(status)
    %w[active suspended deleted].include?(status)
  end

  def valid_size?(size)
    %w[small medium large enterprise].include?(size)
  end
end
