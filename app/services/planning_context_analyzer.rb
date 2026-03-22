# app/services/planning_context_analyzer.rb
# Provides comprehensive analysis of a planning context
# Checks completeness, validates parameters, identifies gaps

class PlanningContextAnalyzer < ApplicationService
  def initialize(planning_context)
    @planning_context = planning_context
  end

  def call
    begin
      analysis = {
        is_complete: check_completeness,
        validation_errors: validate_context,
        missing_parameters: identify_missing_parameters,
        recommendations: generate_recommendations,
        summary: build_summary
      }

      success(data: analysis)
    rescue StandardError => e
      Rails.logger.error("PlanningContextAnalyzer error: #{e.class} - #{e.message}")
      failure(errors: [ e.message ])
    end
  end

  private

  def check_completeness
    return false if @planning_context.request_content.blank?
    return false if @planning_context.detected_intent.blank?
    return false if @planning_context.is_complex && @planning_context.pre_creation_answers.blank?
    return false if @planning_context.hierarchical_items.blank?
    return false if @planning_context.parent_requirements.blank?

    true
  end

  def validate_context
    errors = []

    # Core required fields
    errors << "Missing request_content" if @planning_context.request_content.blank?
    errors << "Missing detected_intent" if @planning_context.detected_intent.blank?
    errors << "Missing planning_domain" if @planning_context.planning_domain.blank?

    # Complex request validations
    if @planning_context.is_complex
      errors << "Missing pre_creation_answers for complex request" if @planning_context.pre_creation_answers.blank?
      errors << "Missing pre_creation_questions for complex request" if @planning_context.pre_creation_questions.blank?
    end

    # Structure validations
    errors << "Missing parent_requirements" if @planning_context.parent_requirements.blank?
    errors << "Missing hierarchical_items" if @planning_context.hierarchical_items.blank?

    errors
  end

  def identify_missing_parameters
    missing = []
    params = @planning_context.parameters || {}

    case @planning_context.planning_domain
    when "event", "roadshow", "conference"
      missing << "locations" unless params[:locations].present?
      missing << "timeline" unless params[:timeline].present? || (params[:start_date].present? && params[:end_date].present?)
      missing << "budget" unless params[:budget].present?
    when "project", "sprint"
      missing << "timeline" unless params[:timeline].present?
      missing << "team_size" unless params[:team_size].present?
    when "vacation", "trip"
      missing << "locations" unless params[:locations].present?
      missing << "timeline" unless params[:timeline].present?
    when "learning", "course"
      missing << "timeline" unless params[:timeline].present?
    end

    missing
  end

  def generate_recommendations
    recommendations = []

    # Complexity recommendations
    if @planning_context.is_complex && @planning_context.pre_creation_answers.blank?
      recommendations << "Collect pre-creation answers for better item generation"
    end

    # Completeness recommendations
    missing_params = identify_missing_parameters
    if missing_params.present?
      recommendations << "Collect missing parameters: #{missing_params.join(', ')}"
    end

    # Item generation recommendations
    if @planning_context.generated_items.blank?
      recommendations << "Generate items for sublists using ItemGenerationService"
    end

    recommendations
  end

  def build_summary
    {
      state: @planning_context.state,
      status: @planning_context.status,
      domain: @planning_context.planning_domain,
      complexity: @planning_context.complexity_level,
      has_parent_items: @planning_context.parent_requirements.dig("items").present?,
      has_generated_items: @planning_context.generated_items.present?,
      has_hierarchical_structure: @planning_context.hierarchical_items.dig("subdivisions").present?,
      parameter_count: (@planning_context.parameters || {}).length,
      confidence: @planning_context.intent_confidence
    }
  end
end
