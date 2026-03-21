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

    case subdivision_type
    when "locations"
      subdivisions = generate_location_subdivisions
    when "phases"
      subdivisions = generate_phase_subdivisions
    when "teams"
      subdivisions = generate_team_subdivisions
    when "none"
      subdivisions = {}
    end

    subdivisions
  end

  def generate_location_subdivisions
    locations = @parameters[:locations] || []
    subdivisions = {}

    locations.each do |location|
      subdivisions[location] = {
        title: location,
        items: generate_location_items(location),
        type: "location_sublist"
      }
    end

    subdivisions
  end

  def generate_location_items(location)
    # Use ItemGenerationService to generate location-specific items
    service = ItemGenerationService.new(
      list_title: @planning_context.request_content,
      description: build_item_context,
      category: @parameters[:category] || "professional",
      planning_context: @planning_context,
      sublist_title: location
    )

    result = service.call
    result.success? ? result.data[:items] : []
  end

  def generate_phase_subdivisions
    timeline = @parameters[:timeline] || ""
    phase_count = infer_phase_count(timeline)
    subdivisions = {}

    phase_names = generate_phase_names(phase_count)
    phase_names.each_with_index do |phase_name, index|
      subdivisions[phase_name] = {
        title: phase_name,
        items: generate_phase_items(phase_name, index + 1, phase_count),
        type: "phase_sublist",
        sequence: index + 1
      }
    end

    subdivisions
  end

  def generate_phase_items(phase_name, phase_num, total_phases)
    service = ItemGenerationService.new(
      list_title: @planning_context.request_content,
      description: "Phase #{phase_num} of #{total_phases}: #{build_item_context}",
      category: @parameters[:category] || "professional",
      planning_context: @planning_context,
      sublist_title: phase_name
    )

    result = service.call
    result.success? ? result.data[:items] : []
  end

  def generate_team_subdivisions
    team_count = (@parameters[:team_size] || 2).to_i
    subdivisions = {}

    team_count.times do |i|
      team_name = "Team #{i + 1}"
      subdivisions[team_name] = {
        title: team_name,
        items: generate_team_items(team_name),
        type: "team_sublist"
      }
    end

    subdivisions
  end

  def generate_team_items(team_name)
    service = ItemGenerationService.new(
      list_title: @planning_context.request_content,
      description: "#{team_name}: #{build_item_context}",
      category: @parameters[:category] || "professional",
      planning_context: @planning_context,
      sublist_title: team_name
    )

    result = service.call
    result.success? ? result.data[:items] : []
  end

  def generate_relationships
    # Track parent-child relationships for database storage
    relationships = []

    # Location relationships
    if @parameters[:locations].present?
      @parameters[:locations].each do |location|
        relationships << {
          parent_type: "main_list",
          child_type: "location_sublist",
          relationship_type: "subdivision",
          metadata: { location: location }
        }
      end
    end

    # Phase relationships
    if @parameters[:timeline].present?
      phase_count = infer_phase_count(@parameters[:timeline])
      phase_count.times do |i|
        relationships << {
          parent_type: "main_list",
          child_type: "phase_sublist",
          relationship_type: "subdivision",
          metadata: { phase_num: i + 1, total_phases: phase_count }
        }
      end
    end

    relationships
  end

  def generate_phase_names(count)
    case count
    when 1
      [ "Initial" ]
    when 2
      [ "Phase 1: Planning", "Phase 2: Execution" ]
    when 3
      [ "Phase 1: Planning", "Phase 2: Development", "Phase 3: Completion" ]
    when 4
      [ "Phase 1: Planning", "Phase 2: Development", "Phase 3: Testing", "Phase 4: Launch" ]
    else
      (1..count).map { |i| "Phase #{i}" }
    end
  end

  def infer_phase_count(timeline)
    timeline = timeline.to_s.downcase

    case timeline
    when /week/
      1
    when /month/
      4
    when /quarter|3.month/
      3
    when /year|6.month/
      4
    when /\d+\s*(?:week|month|day)/
      match = timeline.match(/(\d+)\s*(?:week|month|day)/)
      match[1].to_i if match
    else
      2
    end
  end

  def build_item_context
    context_parts = []
    context_parts << "Budget: #{@parameters[:budget]}" if @parameters[:budget].present?
    context_parts << "Timeline: #{@parameters[:timeline]}" if @parameters[:timeline].present?
    context_parts << "Domain: #{@planning_context.planning_domain}" if @planning_context.planning_domain.present?

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
