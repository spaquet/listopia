# app/services/ai_orchestration_service.rb

class AiOrchestrationService
  include ActiveModel::Model
  include ActiveModel::Attributes

  class TaskAnalysisError < StandardError; end
  class ToolSelectionError < StandardError; end
  class OrchestrationError < StandardError; end

  attr_accessor :user, :context, :chat, :task_decomposer, :workflow_manager

  def initialize(user:, context: {}, chat:)
    @user = user
    @context = context
    @chat = chat
    @logger = Rails.logger
    @task_decomposer = TaskDecompositionService.new(user: user, context: context, chat: chat)
    @workflow_manager = WorkflowManager.new(user: user, context: context, chat: chat)
  end

  # Main orchestration method - analyzes task and determines optimal approach
  def orchestrate_task(user_message)
    @logger.info "AIOrchestrationService: Starting task orchestration for user #{@user.id}"

    begin
      # Step 1: Analyze the task complexity and type
      task_analysis = analyze_task_complexity(user_message)
      @logger.debug "Task analysis result: #{task_analysis}"

      # Step 2: Determine if this needs multi-step planning or direct tool usage
      execution_strategy = determine_execution_strategy(task_analysis)
      @logger.debug "Execution strategy: #{execution_strategy[:type]}"

      # Step 3: Execute based on strategy
      case execution_strategy[:type]
      when :direct_tool_usage
        execute_direct_tool_usage(user_message, task_analysis)
      when :simple_planning
        execute_simple_planning(user_message, task_analysis)
      when :complex_workflow
        execute_complex_workflow(user_message, task_analysis)
      else
        # Fallback to standard conversation
        execute_standard_conversation(user_message)
      end

    rescue => e
      @logger.error "AI Orchestration error: #{e.message}"
      @logger.error e.backtrace.join("\n")

      # Graceful fallback to standard processing
      {
        success: false,
        error: e.message,
        fallback_needed: true,
        user_message: "I'll handle your request using my standard approach. Let me help you with that."
      }
    end
  end

  # Analyze the complexity and type of the user's task
  def analyze_task_complexity(user_message)
    # Use RubyLLM for intelligent task analysis instead of rigid patterns
    analysis_chat = create_analysis_chat

    analysis_prompt = build_task_analysis_prompt(user_message)

    begin
      response = analysis_chat.ask(analysis_prompt)
      parsed_analysis = parse_task_analysis_response(response.content)

      # Validate the analysis
      validate_task_analysis!(parsed_analysis)

      parsed_analysis
    rescue => e
      @logger.error "Task analysis failed: #{e.message}"
      # Fallback to heuristic analysis
      fallback_task_analysis(user_message)
    end
  end

  # Determine the best execution strategy based on task analysis
  def determine_execution_strategy(task_analysis)
    complexity_score = calculate_complexity_score(task_analysis)

    case complexity_score
    when 0..3
      { type: :direct_tool_usage, reason: "Simple, single-tool task" }
    when 4..6
      { type: :simple_planning, reason: "Multi-step task requiring basic planning" }
    when 7..10
      { type: :complex_workflow, reason: "Complex task requiring detailed workflow management" }
    else
      { type: :standard_conversation, reason: "Non-task conversation" }
    end
  end

  # Execute direct tool usage for simple tasks
  def execute_direct_tool_usage(user_message, task_analysis)
    @logger.info "Executing direct tool usage"

    # Let RubyLLM handle tool selection and execution naturally
    # Add context-aware instructions without rigid constraints
    context_instructions = build_context_aware_instructions(task_analysis)

    # Use existing McpService with enhanced context
    enhanced_context = @context.merge({
      task_type: task_analysis[:type],
      execution_strategy: "direct_tool_usage",
      suggested_tools: task_analysis[:suggested_tools]
    })

    mcp_service = McpService.new(user: @user, context: enhanced_context, chat: @chat)

    # Add context instructions to chat if needed
    if context_instructions.present?
      @chat.with_instructions(context_instructions, replace: false)
    end

    result = mcp_service.process_message(user_message)

    {
      success: true,
      result: result,
      strategy: "direct_tool_usage",
      analysis: task_analysis
    }
  end

  # Execute simple planning for multi-step tasks
  def execute_simple_planning(user_message, task_analysis)
    @logger.info "Executing simple planning workflow"

    # Use TaskDecompositionService to break down the task
    decomposition_result = @task_decomposer.decompose_task(user_message, task_analysis)

    unless decomposition_result[:success]
      return {
        success: false,
        error: "Task decomposition failed",
        fallback_needed: true
      }
    end

    # Execute the planning workflow
    workflow_result = @workflow_manager.execute_simple_workflow(
      steps: decomposition_result[:steps],
      context: task_analysis
    )

    {
      success: workflow_result[:success],
      result: workflow_result[:result],
      strategy: "simple_planning",
      steps_completed: workflow_result[:steps_completed],
      analysis: task_analysis
    }
  end

  # Execute complex workflow for sophisticated tasks
  def execute_complex_workflow(user_message, task_analysis)
    @logger.info "Executing complex workflow"

    # Use TaskDecompositionService for detailed breakdown
    decomposition_result = @task_decomposer.decompose_complex_task(user_message, task_analysis)

    unless decomposition_result[:success]
      return {
        success: false,
        error: "Complex task decomposition failed",
        fallback_needed: true
      }
    end

    # Execute the complex workflow with progress tracking
    workflow_result = @workflow_manager.execute_complex_workflow(
      workflow_plan: decomposition_result[:workflow_plan],
      context: task_analysis
    )

    {
      success: workflow_result[:success],
      result: workflow_result[:result],
      strategy: "complex_workflow",
      workflow_id: workflow_result[:workflow_id],
      progress: workflow_result[:progress],
      analysis: task_analysis
    }
  end

  # Fallback to standard conversation handling
  def execute_standard_conversation(user_message)
    @logger.info "Executing standard conversation"

    mcp_service = McpService.new(user: @user, context: @context, chat: @chat)
    result = mcp_service.process_message(user_message)

    {
      success: true,
      result: result,
      strategy: "standard_conversation"
    }
  end

  private

  def create_analysis_chat
    # Create a lightweight chat instance for task analysis
    # This won't interfere with the main conversation
    analysis_chat = @user.chats.build(
      title: "Task Analysis - #{Time.current.to_i}",
      status: "analysis"
    )

    # Don't persist analysis chats
    analysis_chat.model_id = Rails.application.config.mcp.model

    analysis_chat
  end

  def build_task_analysis_prompt(user_message)
    <<~PROMPT
      Analyze this user request and provide a structured assessment:

      User Message: "#{user_message}"

      Please analyze this request and respond with ONLY a JSON object containing:
      {
        "type": "task_management|information_request|conversation|complex_planning",
        "complexity_level": 1-10,
        "requires_tools": true/false,
        "suggested_tools": ["tool_name1", "tool_name2"],
        "multi_step": true/false,
        "dependencies": ["step1", "step2"],
        "urgency": "low|medium|high",
        "context_needed": ["context_type1", "context_type2"],
        "user_intent": "brief description of what user wants to accomplish"
      }

      Only respond with valid JSON. Do not include any other text.
    PROMPT
  end

  def parse_task_analysis_response(response_content)
    # Clean up potential markdown formatting
    json_content = response_content.gsub(/```json\n?/, "").gsub(/```\n?/, "").strip

    begin
      parsed = JSON.parse(json_content, symbolize_names: true)

      # Ensure required fields exist
      parsed[:type] ||= "conversation"
      parsed[:complexity_level] ||= 1
      parsed[:requires_tools] ||= false
      parsed[:suggested_tools] ||= []
      parsed[:multi_step] ||= false
      parsed[:dependencies] ||= []
      parsed[:urgency] ||= "medium"
      parsed[:context_needed] ||= []
      parsed[:user_intent] ||= "General request"

      parsed
    rescue JSON::ParserError => e
      @logger.error "Failed to parse task analysis JSON: #{e.message}"
      @logger.error "Response content: #{response_content}"
      fallback_task_analysis(response_content)
    end
  end

  def validate_task_analysis!(analysis)
    required_fields = [ :type, :complexity_level, :requires_tools ]

    required_fields.each do |field|
      unless analysis.key?(field)
        raise TaskAnalysisError, "Missing required field: #{field}"
      end
    end

    unless (1..10).include?(analysis[:complexity_level])
      raise TaskAnalysisError, "Invalid complexity level: #{analysis[:complexity_level]}"
    end

    valid_types = %w[task_management information_request conversation complex_planning]
    unless valid_types.include?(analysis[:type].to_s)
      raise TaskAnalysisError, "Invalid task type: #{analysis[:type]}"
    end
  end

  def fallback_task_analysis(user_message)
    # Heuristic-based analysis as fallback
    message_lower = user_message.downcase

    # Detect task management patterns
    task_keywords = %w[create add make build plan organize manage schedule]
    planning_keywords = %w[plan planning strategy workflow steps approach]
    list_keywords = %w[list todo task item checklist]

    type = if task_keywords.any? { |kw| message_lower.include?(kw) }
      "task_management"
    elsif planning_keywords.any? { |kw| message_lower.include?(kw) }
      "complex_planning"
    else
      "conversation"
    end

    complexity = if planning_keywords.any? { |kw| message_lower.include?(kw) }
      7
    elsif task_keywords.any? { |kw| message_lower.include?(kw) }
      4
    else
      1
    end

    requires_tools = list_keywords.any? { |kw| message_lower.include?(kw) } ||
                     task_keywords.any? { |kw| message_lower.include?(kw) }

    {
      type: type,
      complexity_level: complexity,
      requires_tools: requires_tools,
      suggested_tools: requires_tools ? [ "list_management_tool" ] : [],
      multi_step: complexity > 3,
      dependencies: [],
      urgency: "medium",
      context_needed: [],
      user_intent: "Extracted from fallback analysis",
      analysis_method: "fallback_heuristic"
    }
  end

  def calculate_complexity_score(task_analysis)
    base_score = task_analysis[:complexity_level] || 1

    # Adjust based on other factors
    score_adjustments = 0
    score_adjustments += 2 if task_analysis[:multi_step]
    score_adjustments += 1 if task_analysis[:dependencies]&.any?
    score_adjustments += 1 if task_analysis[:urgency] == "high"
    score_adjustments -= 1 if task_analysis[:type] == "conversation"

    [ base_score + score_adjustments, 10 ].min
  end

  def build_context_aware_instructions(task_analysis)
    return nil unless task_analysis[:requires_tools]

    instructions = []

    case task_analysis[:type]
    when "task_management"
      instructions << "Focus on helping the user manage their tasks and lists effectively."
      if task_analysis[:suggested_tools]&.include?("list_management_tool")
        instructions << "Use the list management tool to create, update, or organize their lists."
      end
    when "complex_planning"
      instructions << "Break down complex requests into manageable steps."
      instructions << "Create organized plans and track progress systematically."
    end

    if task_analysis[:urgency] == "high"
      instructions << "Prioritize efficiency and quick completion of this request."
    end

    instructions.empty? ? nil : instructions.join(" ")
  end
end
