# app/services/planning_context_handler.rb
# Orchestrates the complete planning context lifecycle
# Coordinates detector, analyzer, and generator services

class ChatContextHandler < ApplicationService
  def initialize(user_message, chat, user, organization)
    @user_message = user_message
    @chat = chat
    @user = user
    @organization = organization
  end

  def call
    begin
      # Step 1: Detect intent and create planning context if needed
      detector_result = PlanningContextDetector.new(
        @user_message,
        @chat,
        @user,
        @organization
      ).call

      return detector_result unless detector_result.success?

      detector_data = detector_result.data
      return success(data: detector_data) unless detector_data[:should_create_context]

      planning_context = detector_data[:planning_context]

      # Step 2: Analyze parent requirements based on domain
      analyzer_result = ParentRequirementsAnalyzer.new(planning_context).call
      return analyzer_result unless analyzer_result.success?

      planning_context = analyzer_result.data[:planning_context]

      # Step 3: For simple requests, go straight to generating hierarchical items
      if !planning_context.is_complex
        return generate_items_for_context(planning_context)
      end

      # Step 4: For complex requests, mark as awaiting answers
      planning_context.mark_awaiting_answers!

      success(data: {
        planning_context: planning_context,
        requires_user_input: true,
        next_step: "pre_creation_planning"
      })
    rescue StandardError => e
      Rails.logger.error("ChatContextHandler error: #{e.class} - #{e.message}")
      failure(errors: [ e.message ])
    end
  end

  # Process user answers and generate items
  def process_answers(planning_context, answers_hash)
    begin
      # Step 1: Extract and map parameters from answers
      mapper_result = ParameterMapperService.new(planning_context, answers_hash).call
      return mapper_result unless mapper_result.success?

      planning_context = mapper_result.data[:planning_context]

      # Step 2: Analyze parent requirements (needed for hierarchical item generation)
      analyzer_result = ParentRequirementsAnalyzer.new(planning_context).call
      return analyzer_result unless analyzer_result.success?

      planning_context = analyzer_result.data[:planning_context]

      # Step 3: Generate hierarchical items
      generate_items_for_context(planning_context)
    rescue StandardError => e
      Rails.logger.error("ChatContextHandler#process_answers error: #{e.class} - #{e.message}")
      failure(errors: [ e.message ])
    end
  end

  # Generate all items for the planning context
  def generate_items_for_context(planning_context)
    begin
      # Update status to processing
      planning_context.mark_processing!

      # Step 1: Generate hierarchical structure
      hierarchy_result = HierarchicalItemGenerator.new(planning_context).call
      return hierarchy_result unless hierarchy_result.success?

      planning_context = hierarchy_result.data[:planning_context]

      # Step 2: Analyze completeness
      analysis_result = PlanningContextAnalyzer.new(planning_context).call
      return analysis_result unless analysis_result.success?

      analysis = analysis_result.data

      # Step 3: Mark as complete
      planning_context.mark_complete!

      success(data: {
        planning_context: planning_context,
        analysis: analysis,
        ready_for_list_creation: analysis[:is_complete]
      })
    rescue StandardError => e
      Rails.logger.error("ChatContextHandler#generate_items_for_context error: #{e.class} - #{e.message}")
      planning_context.mark_error!(e.message) if planning_context
      failure(errors: [ e.message ])
    end
  end
end
