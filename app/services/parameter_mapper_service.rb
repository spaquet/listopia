# app/services/parameter_mapper_service.rb
# Maps user answers to structured parameters for planning context
# Handles extraction from pre-creation planning answers and user input

class ParameterMapperService < ApplicationService
  def initialize(planning_context, answers_hash = nil)
    @planning_context = planning_context
    @answers = answers_hash || {}
  end

  def call
    begin
      # If we have pre-creation answers, extract parameters from them
      if @answers.present?
        parameters = extract_from_answers(@answers)
      else
        # Use existing parameters
        parameters = @planning_context.parameters || {}
      end

      # Enrich with domain-specific parameter extraction
      enriched_params = enrich_parameters(parameters)

      # Update planning context with extracted parameters
      @planning_context.add_parameters(enriched_params)

      success(data: {
        parameters: enriched_params,
        planning_context: @planning_context
      })
    rescue StandardError => e
      Rails.logger.error("ParameterMapperService error: #{e.class} - #{e.message}")
      failure(errors: [ e.message ])
    end
  end

  private

  def extract_from_answers(answers_hash)
    parameters = {}

    # Common parameters
    parameters[:title] = answers_hash["title"] if answers_hash["title"].present?
    parameters[:description] = answers_hash["description"] if answers_hash["description"].present?
    parameters[:timeline] = answers_hash["timeline"] if answers_hash["timeline"].present?
    parameters[:budget] = answers_hash["budget"] if answers_hash["budget"].present?

    # Location-based parameters
    if answers_hash["locations"].present?
      locations = answers_hash["locations"]
      parameters[:locations] = locations.is_a?(String) ? locations.split(",").map(&:strip) : locations
    end

    # Dates
    parameters[:start_date] = answers_hash["start_date"] if answers_hash["start_date"].present?
    parameters[:end_date] = answers_hash["end_date"] if answers_hash["end_date"].present?

    # Categories/types
    parameters[:category] = answers_hash["category"] if answers_hash["category"].present?
    parameters[:type] = answers_hash["type"] if answers_hash["type"].present?

    # People/resources
    parameters[:team_size] = answers_hash["team_size"] if answers_hash["team_size"].present?
    parameters[:participants] = answers_hash["participants"] if answers_hash["participants"].present?

    parameters
  end

  def enrich_parameters(base_params)
    parameters = base_params.dup

    # Determine subdivision strategy based on parameters
    if parameters[:locations].present? && parameters[:locations].is_a?(Array)
      parameters[:subdivision_type] = "locations"
      parameters[:subdivision_count] = parameters[:locations].length
    elsif parameters[:timeline].present? || (parameters[:start_date].present? && parameters[:end_date].present?)
      # Infer phases/weeks from timeline
      parameters[:subdivision_type] = "phases"
      parameters[:subdivision_count] = infer_phase_count(parameters)
    elsif parameters[:team_size].present? && parameters[:team_size].to_i > 1
      parameters[:subdivision_type] = "teams"
    end

    # Classify complexity if not already done
    parameters[:domain_hint] = @planning_context.planning_domain if @planning_context.planning_domain.present?

    parameters
  end

  def infer_phase_count(parameters)
    # Try to infer number of phases from timeline description
    timeline = parameters[:timeline].to_s.downcase

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
      # Extract number if present
      match = timeline.match(/(\d+)\s*(?:week|month|day)/)
      match[1].to_i if match
    else
      2 # Default to 2 phases
    end
  end
end
