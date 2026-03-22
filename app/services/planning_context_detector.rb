# app/services/planning_context_detector.rb
# Analyzes the initial user request and creates a PlanningContext
# Detects intent, complexity, planning domain, and initial parameters

class PlanningContextDetector < ApplicationService
  def initialize(user_message, chat, user, organization)
    @user_message = user_message
    @chat = chat
    @user = user
    @organization = organization
  end

  def call
    begin
      # Check if planning context already exists for this chat
      if @chat.planning_context.present?
        Rails.logger.info("PlanningContextDetector - Planning context already exists for chat #{@chat.id}, returning existing context")
        return success(data: {
          should_create_context: false,
          planning_context: @chat.planning_context,
          reasoning: "Planning context already exists"
        })
      end

      # Use CombinedIntentComplexityService to analyze the request
      analysis_result = CombinedIntentComplexityService.new(
        user_message: @user_message,
        chat: @chat,
        user: @user,
        organization: @organization
      ).call

      return failure(errors: [ "Intent detection failed" ]) unless analysis_result.success?

      analysis_data = analysis_result.data

      # Check if this is a create_list intent - if not, return without creating context
      unless analysis_data[:intent] == "create_list"
        return success(data: {
          should_create_context: false,
          intent: analysis_data[:intent],
          reasoning: "Non-list creation intent"
        })
      end

      # Create planning context for list creation
      planning_context = PlanningContext.create!(
        user: @user,
        chat: @chat,
        organization: @organization,
        request_content: @user_message.content,
        detected_intent: analysis_data[:intent],
        intent_confidence: analysis_data[:confidence] || 0.0,
        planning_domain: analysis_data[:planning_domain] || "general",
        complexity_level: analysis_data[:is_complex] ? "complex" : "simple",
        is_complex: analysis_data[:is_complex],
        complexity_reasoning: analysis_data[:complexity_reasoning],
        parameters: analysis_data[:parameters] || {},
        state: :initial,
        status: analysis_data[:is_complex] ? :analyzing : :processing
      )

      # Store thinking tokens if available (from extended thinking)
      if analysis_data[:thinking_tokens].present?
        planning_context.set_metadata("thinking_tokens", analysis_data[:thinking_tokens])
      end

      success(data: {
        should_create_context: true,
        planning_context: planning_context,
        is_complex: analysis_data[:is_complex],
        planning_domain: analysis_data[:planning_domain],
        parameters: analysis_data[:parameters]
      })
    rescue StandardError => e
      Rails.logger.error("PlanningContextDetector error: #{e.class} - #{e.message}")
      failure(errors: [ e.message ])
    end
  end
end
