# app/services/hierarchical_item_generator.rb
# Generates the complete hierarchical structure of items
# Creates parent items + subdivisions + child items based on planning context

class HierarchicalItemGenerator < ApplicationService
  def initialize(planning_context)
    @planning_context = planning_context
    @parameters = planning_context.parameters || {}
  end

  def call
    begin
      # Generate parent-level items first
      parent_items = @planning_context.parent_requirements.dig("items") || []

      # Determine subdivision strategy
      subdivision_type = @parameters[:subdivision_type] || infer_subdivision_type

      # Generate hierarchical structure with subdivisions
      hierarchical_items = {
        parent_items: parent_items,
        subdivisions: generate_subdivisions(subdivision_type),
        relationships: generate_relationships,
        subdivision_type: subdivision_type
      }

      # Update planning context
      @planning_context.update!(
        hierarchical_items: hierarchical_items,
        generated_items: build_flat_items_list(hierarchical_items)
      )

      success(data: {
        hierarchical_items: hierarchical_items,
        planning_context: @planning_context
      })
    rescue StandardError => e
      Rails.logger.error("HierarchicalItemGenerator error: #{e.class} - #{e.message}")
      failure(errors: [ e.message ])
    end
  end

  private

  def infer_subdivision_type
    return "locations" if @parameters[:locations].present?
    return "phases" if @parameters[:timeline].present?
    return "teams" if @parameters[:team_size].present? && @parameters[:team_size].to_i > 1
    "none"
  end

  def generate_subdivisions(subdivision_type)
    subdivisions = {}
    return {} if subdivision_type == "none"

    # Generic subdivision generation based on detected type and parameter key
    subdivision_key = @parameters[:subdivision_key] || subdivision_type
    subdivision_data = @parameters[subdivision_key.to_sym] || @parameters[subdivision_key]

    return {} unless subdivision_data.present?

    # Handle both array and non-array subdivision data
    items_to_subdivide = subdivision_data.is_a?(Array) ? subdivision_data : [subdivision_data]

    items_to_subdivide.each do |item|
      item_title = item.is_a?(Hash) ? (item[:title] || item["title"] || item.to_s) : item.to_s

      subdivisions[item_title] = {
        title: item_title,
        items: generate_sublist_items(item_title, subdivision_type),
        type: "#{subdivision_type}_sublist"
      }
    end

    subdivisions
end

  def generate_sublist_items(subdivision_title, subdivision_type)
    # Use ItemGenerationService to generate items specific to this subdivision
    service = ItemGenerationService.new(
      list_title: @planning_context.request_content,
      description: build_item_context(subdivision_type),
      category: @parameters[:category] || "professional",
      planning_context: @planning_context,
      sublist_title: subdivision_title,
      subdivision_type: subdivision_type
    )

    result = service.call
    result.success? ? result.data[:items] : []
  end

  def generate_relationships
    # Track parent-child relationships for database storage (generic for any subdivision type)
    relationships = []
    subdivision_type = @parameters[:subdivision_type] || "none"

    if subdivision_type != "none" && @parameters[:subdivision_count].to_i > 0
      @parameters[:subdivision_count].to_i.times do |i|
        relationships << {
          parent_type: "main_list",
          child_type: "#{subdivision_type}_sublist",
          relationship_type: "subdivision",
          metadata: { subdivision_index: i + 1, total_subdivisions: @parameters[:subdivision_count] }
        }
      end
    end

    relationships
  end

  def build_item_context(subdivision_type = nil)
    context_parts = []
    context_parts << "Budget: #{@parameters[:budget]}" if @parameters[:budget].present?
    context_parts << "Timeline: #{@parameters[:timeline]}" if @parameters[:timeline].present?
    context_parts << "Domain: #{@planning_context.planning_domain}" if @planning_context.planning_domain.present?
    context_parts << "Subdivision: #{subdivision_type}" if subdivision_type.present?

    context_parts.join(" | ")
  end

  def build_flat_items_list(hierarchical)
    items = hierarchical[:parent_items] || []

    # Flatten subdivision items
    (hierarchical[:subdivisions] || {}).each do |_sublist_name, sublist_data|
      items.concat(sublist_data[:items] || [])
    end

    items
  end
end
