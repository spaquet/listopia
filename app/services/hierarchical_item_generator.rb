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

      # Generate hierarchical structure with subdivisions (generic - uses whatever data is present)
      subdivisions = generate_subdivisions(nil)

      hierarchical_items = {
        parent_items: parent_items,
        subdivisions: subdivisions,
        relationships: generate_relationships,
        subdivision_type: subdivisions.any? ? "auto_detected" : "none"
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

  def generate_subdivisions(subdivision_type)
    subdivisions = {}

    # GENERIC approach: Look for ANY array data in parameters and create subdivisions from it
    # Don't wait for perfect classification - just use what we have
    # This is domain-agnostic: works for locations, phases, topics, teams, etc.

    # Priority order: check for common subdivision sources
    subdivision_sources = [
      [ :locations, "location" ],
      [ :phases, "phase" ],
      [ :topics, "topic" ],
      [ :modules, "module" ],
      [ :books, "book" ],
      [ :teams, "team" ],
      [ :team_members, "team member" ],
      [ :activities, "activity" ]
    ]

    subdivision_sources.each do |param_key, label_singular|
      # Access with both symbol and string keys (parameters may come from JSON with string keys)
      data = @parameters[param_key] || @parameters[param_key.to_s]

      if data.present? && data.is_a?(Array) && data.length > 0
        # Found array data - create subdivisions from it
        data.each do |item|
          item_title = item.is_a?(Hash) ? (item[:title] || item["title"] || item.to_s) : item.to_s
          next if item_title.blank?

          subdivisions[item_title] = {
            title: item_title,
            items: generate_sublist_items(item_title, param_key.to_s),
            type: "sublist"
          }
        end

        # Stop after first source found (prioritized by order above)
        break if subdivisions.any?
      end
    end

    subdivisions
  end

  def generate_sublist_items(subdivision_title, subdivision_type)
    # Use ItemGenerationService to generate items specific to this subdivision
    # For hierarchical (nested) lists, always use "planning" since these are generated
    # from complex requests that break down into planning steps for each subdivision
    service = ItemGenerationService.new(
      list_title: @planning_context.request_content,
      description: build_item_context(subdivision_type),
      category: (@parameters[:category] || @parameters["category"] || "professional"),
      planning_context: @parameters,
      sublist_title: subdivision_title,
      generation_type: "planning"
    )

    result = service.call
    result.success? ? result.data : []
  end

  def generate_relationships
    # Track parent-child relationships (generic - doesn't need to know subdivision type)
    relationships = []
    # Relationships are implicit in the parent_list_id database column
    # This is just metadata for tracking
    relationships
  end

  def build_item_context(subdivision_type = nil)
    context_parts = []
    budget = @parameters[:budget] || @parameters["budget"]
    timeline = @parameters[:timeline] || @parameters["timeline"]

    context_parts << "Budget: #{budget}" if budget.present?
    context_parts << "Timeline: #{timeline}" if timeline.present?
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
