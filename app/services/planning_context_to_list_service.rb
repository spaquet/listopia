# app/services/planning_context_to_list_service.rb
# Converts a completed PlanningContext into an actual List with items and sublists
# Final step of the planning journey: context → structure → actual resources

class PlanningContextToListService < ApplicationService
  def initialize(planning_context, user, organization)
    @planning_context = planning_context
    @user = user
    @organization = organization
  end

  def call
    begin
      # Verify planning context is ready
      unless @planning_context.state == "completed"
        return failure(errors: [ "Planning context must be in completed state, currently: #{@planning_context.state}" ])
      end

      unless @planning_context.hierarchical_items.present?
        return failure(errors: [ "No hierarchical items generated in planning context" ])
      end

      # Build list structure from planning context
      list_structure = build_list_structure

      # Create the list using ListCreationService
      list_result = create_list_from_structure(list_structure)
      return list_result unless list_result.success?

      list = list_result.data

      # Update planning context with reference to created list
      @planning_context.update!(
        list_created_id: list.id,
        state: :resource_creation
      )

      success(data: {
        list: list,
        planning_context: @planning_context,
        items_count: list.list_items.count,
        sublists_count: list.sub_lists.count
      })
    rescue StandardError => e
      Rails.logger.error("PlanningContextToListService error: #{e.class} - #{e.message}")
      failure(errors: [ e.message ])
    end
  end

  private

  def build_list_structure
    hierarchical = @planning_context.hierarchical_items || {}

    {
      title: extract_title,
      description: @planning_context.request_content,
      items: build_parent_items,
      nested_lists: build_nested_lists,
      organization: @organization,
      status: :active,
      list_type: determine_list_type
    }
  end

  def determine_list_type
    # Map planning domain to valid list_type
    case @planning_context.planning_domain
    when 'event', 'project', 'travel', 'learning'
      'professional'
    else
      'personal'
    end
  end

  def extract_title
    # Try to extract title from request content
    request = @planning_context.request_content || ""

    # Use first line if available
    title = request.split("\n").first.strip
    return title if title.present? && title.length < 100

    # Fallback to parameters
    title = @planning_context.parameters[:title]
    return title if title.present?

    # Last resort: generate from domain
    "#{@planning_context.planning_domain.titleize} Plan"
  end

  def build_parent_items
    # Use parent items from requirements analysis
    parent_reqs = @planning_context.parent_requirements || {}
    parent_items = parent_reqs["items"] || []

    parent_items.map do |item|
      {
        title: item[:title] || item["title"],
        description: item[:description] || item["description"],
        priority: item[:priority] || item["priority"] || "medium",
        type: item[:type] || item["type"]
      }
    end
  end

  def build_nested_lists
    hierarchical = @planning_context.hierarchical_items || {}
    subdivisions = hierarchical["subdivisions"] || {}
    subdivision_type = hierarchical["subdivision_type"] || "none"

    return [] if subdivisions.empty?

    nested_lists = []

    subdivisions.each do |sublist_name, sublist_data|
      nested_list = {
        title: sublist_data[:title] || sublist_data["title"] || sublist_name,
        description: sublist_data[:description] || sublist_data["description"] || "#{subdivision_type.titleize}: #{sublist_name}",
        items: build_sublist_items(sublist_data),
        type: sublist_data[:type] || sublist_data["type"] || "sublist"
      }

      nested_lists << nested_list
    end

    nested_lists
  end

  def build_sublist_items(sublist_data)
    # Handle both symbol and string keys (JSONB returns strings)
    items = sublist_data[:items] || sublist_data["items"] || []

    items.map do |item|
      # Items from ItemGenerationService have: title, description, priority, type
      {
        title: item[:title] || item["title"],
        description: item[:description] || item["description"],
        priority: item[:priority] || item["priority"] || "medium",
        type: item[:type] || item["type"]
      }
    end
  end

  def create_list_from_structure(structure)
    service = ListCreationService.new(@user)

    result = service.create_list_with_structure(
      title: structure[:title],
      description: structure[:description],
      items: structure[:items],
      nested_lists: structure[:nested_lists],
      organization: structure[:organization],
      status: structure[:status],
      list_type: structure[:list_type]
    )

    result
  end
end
