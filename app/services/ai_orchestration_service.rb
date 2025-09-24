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
    @chat = chat # Now properly utilized throughout
    @logger = Rails.logger

    # Initialize services with the chat parameter for context continuity
    @task_decomposer = TaskDecompositionService.new(user: user, context: context, chat: chat)
    @workflow_manager = WorkflowManager.new(user: user, context: context, chat: chat) if defined?(WorkflowManager)

    # Initialize context manager for better chat integration
    @context_manager = ConversationContextManager.new(user: user, chat: chat, current_context: context)
  end

  # Main orchestration method - analyzes task and determines optimal approach
  def orchestrate_task(user_message)
    @logger.info "AIOrchestrationService: Starting task orchestration for user #{@user.id} in chat #{@chat.id}"

    begin
      # Step 1: Analyze the task complexity and type using chat context
      task_analysis = analyze_task_complexity(user_message)
      @logger.debug "Task analysis result: #{task_analysis}"

      # Step 2: Enhance analysis with conversation context
      enhanced_analysis = enhance_analysis_with_chat_context(task_analysis, user_message)
      @logger.debug "Enhanced analysis with chat context: #{enhanced_analysis}"

      # Step 3: Determine if this needs multi-step planning or direct tool usage
      execution_strategy = determine_execution_strategy(enhanced_analysis)
      @logger.debug "Execution strategy: #{execution_strategy[:type]}"

      # Step 4: Execute based on strategy with chat context
      case execution_strategy[:type]
      when :direct_tool_usage
        execute_direct_tool_usage(user_message, enhanced_analysis)
      when :simple_planning
        execute_simple_planning(user_message, enhanced_analysis)
      when :complex_workflow
        execute_complex_workflow(user_message, enhanced_analysis)
      else
        # Fallback to standard conversation with chat context
        execute_standard_conversation(user_message)
      end

    rescue => e
      @logger.error "AI Orchestration error: #{e.message}"
      @logger.error e.backtrace.join("\n")

      # Track the error for conversation context
      @context_manager.track_action(
        action: "orchestration_error",
        entity: @chat,
        metadata: {
          error_type: e.class.name,
          error_message: e.message,
          user_message: user_message.truncate(100)
        }
      )

      # Graceful fallback to standard processing
      {
        success: false,
        error: e.message,
        fallback_needed: true,
        user_message: "I'll handle your request using my standard approach. Let me help you with that.",
        chat_context: {
          chat_id: @chat.id,
          error_occurred: true
        }
      }
    end
  end

  # Analyze task complexity using chat context for better insights
  def analyze_task_complexity(user_message)
    @logger.info "Analyzing task complexity with chat context"

    begin
      # Get conversation context to inform analysis
      conversation_context = @context_manager.build_context_summary

      # Use the original chat for analysis but with specific instructions
      analysis_chat = prepare_chat_for_analysis(conversation_context)

      # Build analysis prompt with conversation context
      analysis_prompt = build_task_analysis_prompt_with_context(user_message, conversation_context)

      # Get AI analysis
      response = analysis_chat.ask(analysis_prompt)

      # Parse and validate analysis
      task_analysis = parse_task_analysis_response(response.content)
      validate_task_analysis!(task_analysis)

      # Track the analysis action
      @context_manager.track_action(
        action: "task_analysis_completed",
        entity: @chat,
        metadata: {
          complexity_level: task_analysis[:complexity_level],
          task_type: task_analysis[:type],
          requires_tools: task_analysis[:requires_tools],
          multi_step: task_analysis[:multi_step]
        }
      )

      task_analysis

    rescue => e
      @logger.error "Task analysis failed: #{e.message}"
      # Fallback to heuristic analysis with chat context
      fallback_task_analysis(user_message, conversation_context)
    end
  end

  # Enhance task analysis with conversation context
  def enhance_analysis_with_chat_context(task_analysis, user_message)
    enhanced_analysis = task_analysis.dup

    # Add chat-specific context
    enhanced_analysis[:chat_context] = {
      chat_id: @chat.id,
      chat_title: @chat.title,
      message_count: @chat.messages.count,
      has_recent_activity: @user.has_recent_activity?(hours: 1)
    }

    # Enhance complexity based on conversation history
    if @chat.messages.count > 5
      # User has been having an extended conversation, might need more context-aware responses
      enhanced_analysis[:context_complexity_boost] = 1
      enhanced_analysis[:complexity_level] = [ enhanced_analysis[:complexity_level] + 1, 10 ].min
    end

    # Check for references to existing lists or items in current context
    if @context[:list_id].present?
      current_list = List.find_by(id: @context[:list_id])
      if current_list&.readable_by?(@user)
        enhanced_analysis[:current_list_context] = {
          list_id: current_list.id,
          list_title: current_list.title,
          list_status: current_list.status,
          items_count: current_list.list_items.count
        }
        # Boost complexity if working with existing complex list
        if current_list.list_items.count > 10
          enhanced_analysis[:context_complexity_boost] = (enhanced_analysis[:context_complexity_boost] || 0) + 1
          enhanced_analysis[:complexity_level] = [ enhanced_analysis[:complexity_level] + 1, 10 ].min
        end
      end
    end

    # Add user's list management patterns
    user_patterns = analyze_user_patterns
    enhanced_analysis[:user_patterns] = user_patterns

    enhanced_analysis
  end

  # Analyze user's list management patterns from conversation history
  def analyze_user_patterns
    recent_contexts = @user.conversation_contexts
                          .where(chat: @chat)
                          .recent
                          .limit(20)
                          .includes(:entity)

    patterns = {
      prefers_detailed_lists: recent_contexts.count > 10,
      creates_complex_structures: false,
      uses_dependencies: false,
      collaboration_active: false
    }

    # Check for complex structures
    list_contexts = recent_contexts.where(entity_type: "List")
    if list_contexts.any?
      complex_lists = list_contexts.select do |context|
        list = context.entity
        list && list.list_items.count > 5
      end
      patterns[:creates_complex_structures] = complex_lists.count > (list_contexts.count * 0.3)
    end

    # Check for collaborative patterns
    collaborative_actions = recent_contexts.where(action: [ "share_list", "add_collaborator", "accept_collaboration" ])
    patterns[:collaboration_active] = collaborative_actions.any?

    patterns
  end

  # Determine execution strategy based on enhanced analysis
  def determine_execution_strategy(enhanced_analysis)
    complexity = enhanced_analysis[:complexity_level] || 1
    requires_tools = enhanced_analysis[:requires_tools] || false
    multi_step = enhanced_analysis[:multi_step] || false
    user_patterns = enhanced_analysis[:user_patterns] || {}

    strategy = {
      type: :standard_conversation,
      reasoning: "Default strategy",
      confidence: 0.5
    }

    # Direct tool usage for simple, single-step tasks
    if complexity <= 3 && requires_tools && !multi_step
      strategy = {
        type: :direct_tool_usage,
        reasoning: "Simple task requiring specific tools",
        confidence: 0.8
      }
    end

    # Simple planning for moderate complexity multi-step tasks
    if complexity >= 4 && complexity <= 6 && multi_step
      strategy = {
        type: :simple_planning,
        reasoning: "Multi-step task with moderate complexity",
        confidence: 0.7
      }
    end

    # Complex workflow for high complexity or user patterns indicating preference
    if complexity >= 7 || (complexity >= 5 && user_patterns[:creates_complex_structures])
      strategy = {
        type: :complex_workflow,
        reasoning: "High complexity task or user prefers detailed structures",
        confidence: 0.9
      }
    end

    # Override based on specific patterns
    if enhanced_analysis[:type] == "complex_planning"
      strategy[:type] = :complex_workflow
      strategy[:reasoning] = "Task explicitly requires complex planning"
      strategy[:confidence] = 0.95
    end

    @logger.debug "Strategy determination: #{strategy}"
    strategy
  end

  # Execute direct tool usage with chat context
  def execute_direct_tool_usage(user_message, enhanced_analysis)
    @logger.info "Executing direct tool usage with chat context"

    # Create MCP service with the same chat context
    mcp_service = McpService.new(user: @user, context: @context, chat: @chat)

    # Add context-specific instructions if needed
    if enhanced_analysis[:current_list_context].present?
      list_context = enhanced_analysis[:current_list_context]
      context_instructions = "You are working with the list '#{list_context[:list_title]}' which currently has #{list_context[:items_count]} items and is #{list_context[:list_status]}. Consider this context when processing the user's request."
      @chat.with_instructions(context_instructions, replace: false)
    end

    result = mcp_service.process_message(user_message)

    # Track the direct tool usage
    @context_manager.track_action(
      action: "direct_tool_usage_completed",
      entity: @chat,
      metadata: {
        user_message: user_message.truncate(100),
        had_list_context: enhanced_analysis[:current_list_context].present?
      }
    )

    {
      success: true,
      result: result,
      strategy: "direct_tool_usage",
      analysis: enhanced_analysis,
      chat_context: {
        chat_id: @chat.id,
        context_used: enhanced_analysis[:current_list_context].present?
      }
    }
  end

  # Execute simple planning with enhanced chat context
  def execute_simple_planning(user_message, enhanced_analysis)
    @logger.info "Executing simple planning workflow with chat context"

    # Use TaskDecompositionService with chat context
    decomposition_result = @task_decomposer.decompose_task(user_message, enhanced_analysis)

    unless decomposition_result[:success]
      return {
        success: false,
        error: "Task decomposition failed",
        fallback_needed: true,
        chat_context: {
          chat_id: @chat.id,
          decomposition_failed: true
        }
      }
    end

    # Execute the planning workflow using workflow manager if available
    if @workflow_manager
      workflow_result = @workflow_manager.execute_simple_workflow(
        steps: decomposition_result[:steps],
        context: enhanced_analysis,
        chat: @chat
      )
    else
      # Fallback: return the decomposition result as the workflow result
      workflow_result = {
        success: true,
        result: "Created #{decomposition_result[:created_lists]&.count || 0} lists from task decomposition",
        steps_completed: decomposition_result[:steps].count
      }
    end

    {
      success: workflow_result[:success],
      result: workflow_result[:result],
      strategy: "simple_planning",
      steps_completed: workflow_result[:steps_completed] || decomposition_result[:steps].count,
      created_lists: decomposition_result[:created_lists],
      analysis: enhanced_analysis,
      chat_context: {
        chat_id: @chat.id,
        decomposition_success: true,
        lists_created: decomposition_result[:created_lists]&.count || 0
      }
    }
  end

  # Execute complex workflow with comprehensive chat context
  def execute_complex_workflow(user_message, enhanced_analysis)
    @logger.info "Executing complex workflow with chat context"

    # Use TaskDecompositionService for detailed breakdown with chat context
    decomposition_result = @task_decomposer.decompose_complex_task(user_message, enhanced_analysis)

    unless decomposition_result[:success]
      return {
        success: false,
        error: "Complex task decomposition failed",
        fallback_needed: true,
        chat_context: {
          chat_id: @chat.id,
          complex_decomposition_failed: true
        }
      }
    end

    # Execute the complex workflow with progress tracking
    if @workflow_manager
      workflow_result = @workflow_manager.execute_complex_workflow(
        workflow_plan: decomposition_result[:workflow_plan],
        context: enhanced_analysis,
        chat: @chat
      )
    else
      # Fallback: return the decomposition result as the workflow result
      workflow_result = {
        success: true,
        result: "Created complex workflow with #{decomposition_result[:total_phases]} phases",
        workflow_id: decomposition_result[:created_lists]&.first&.id,
        progress: {
          phases_created: decomposition_result[:total_phases],
          lists_created: decomposition_result[:created_lists]&.count || 0
        }
      }
    end

    {
      success: workflow_result[:success],
      result: workflow_result[:result],
      strategy: "complex_workflow",
      workflow_id: workflow_result[:workflow_id],
      progress: workflow_result[:progress],
      created_lists: decomposition_result[:created_lists],
      analysis: enhanced_analysis,
      chat_context: {
        chat_id: @chat.id,
        workflow_complexity: decomposition_result[:total_phases],
        lists_created: decomposition_result[:created_lists]&.count || 0
      }
    }
  end

  # Fallback to standard conversation handling with chat context preservation
  def execute_standard_conversation(user_message)
    @logger.info "Executing standard conversation with chat context preservation"

    # Use MCP service with the original chat to maintain conversation flow
    mcp_service = McpService.new(user: @user, context: @context, chat: @chat)
    result = mcp_service.process_message(user_message)

    # Track standard conversation handling
    @context_manager.track_action(
      action: "standard_conversation_handled",
      entity: @chat,
      metadata: {
        user_message: user_message.truncate(100),
        response_length: result&.length || 0
      }
    )

    {
      success: true,
      result: result,
      strategy: "standard_conversation",
      chat_context: {
        chat_id: @chat.id,
        maintained_conversation_flow: true
      }
    }
  end

  private

  # Prepare the original chat for task analysis
  def prepare_chat_for_analysis(conversation_context)
    # Add analysis-specific instructions while preserving conversation context
    analysis_instructions = build_analysis_system_instructions(conversation_context)
    @chat.with_instructions(analysis_instructions, replace: false)
    @chat
  end

  # Build system instructions for analysis
  def build_analysis_system_instructions(conversation_context)
    instructions = [ "You are analyzing a user request for task complexity and requirements. Consider the conversation context:" ]

    if conversation_context[:current_list].present?
      list = conversation_context[:current_list]
      instructions << "User is currently viewing '#{list[:title]}' (#{list[:items_count]} items, #{list[:status]})"
    end

    if conversation_context[:recent_actions].present?
      actions = conversation_context[:recent_actions].keys.join(", ")
      instructions << "Recent user actions: #{actions}"
    end

    instructions << "Analyze the request considering this context and respond with structured JSON analysis."
    instructions.join("\n\n")
  end

  def build_task_analysis_prompt_with_context(user_message, conversation_context)
    context_info = ""

    if conversation_context[:current_list].present?
      list = conversation_context[:current_list]
      context_info += "\nCurrent context: User is viewing '#{list[:title]}' with #{list[:items_count]} items (status: #{list[:status]})"
    end

    if conversation_context[:recent_actions].present? && conversation_context[:recent_actions].any?
      recent_actions = conversation_context[:recent_actions].keys.first(3).join(", ")
      context_info += "\nRecent activity: #{recent_actions}"
    end

    if conversation_context[:available_entities].present?
      entities = conversation_context[:available_entities]
      context_info += "\nUser has #{entities[:owned_lists]} owned lists, #{entities[:accessible_lists]} total accessible lists"
    end

    <<~PROMPT
      Analyze this user request for task complexity and requirements:

      User Message: "#{user_message}"

      #{context_info}

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
        "user_intent": "brief description of what user wants to accomplish",
        "conversation_context_relevance": "how relevant is the current conversation context",
        "list_management_scope": "none|single_list|multiple_lists|complex_workflow"
      }

      Consider the conversation context when determining complexity and requirements.
      Only respond with valid JSON.
    PROMPT
  end

  def parse_task_analysis_response(response_content)
    # Clean up potential markdown formatting
    json_content = response_content.gsub(/```json\n?/, "").gsub(/```\n?/, "").strip

    begin
      parsed = JSON.parse(json_content, symbolize_names: true)

      # Ensure required fields exist with context-aware defaults
      parsed[:type] ||= "conversation"
      parsed[:complexity_level] ||= 1
      parsed[:requires_tools] ||= false
      parsed[:suggested_tools] ||= []
      parsed[:multi_step] ||= false
      parsed[:dependencies] ||= []
      parsed[:urgency] ||= "medium"
      parsed[:context_needed] ||= []
      parsed[:user_intent] ||= "General request"
      parsed[:conversation_context_relevance] ||= "medium"
      parsed[:list_management_scope] ||= "none"

      parsed
    rescue JSON::ParserError => e
      @logger.error "Failed to parse task analysis JSON: #{e.message}"
      @logger.error "Response content: #{response_content}"
      fallback_task_analysis(user_message)
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

    true
  end

  def fallback_task_analysis(user_message, conversation_context = {})
    @logger.info "Using fallback task analysis with conversation context"

    # Heuristic analysis based on message content and context
    analysis = {
      type: "conversation",
      complexity_level: 1,
      requires_tools: false,
      suggested_tools: [],
      multi_step: false,
      dependencies: [],
      urgency: "medium",
      context_needed: [],
      user_intent: "Process user request",
      conversation_context_relevance: "unknown",
      list_management_scope: "none"
    }

    # Simple heuristics based on keywords and context
    message_lower = user_message.downcase

    # Check for task management keywords
    task_keywords = [ "create", "add", "make", "list", "todo", "task", "plan", "organize" ]
    if task_keywords.any? { |keyword| message_lower.include?(keyword) }
      analysis[:type] = "task_management"
      analysis[:requires_tools] = true
      analysis[:suggested_tools] = [ "list_management_tool" ]
      analysis[:list_management_scope] = "single_list"
    end

    # Check for planning keywords
    planning_keywords = [ "workflow", "project", "strategy", "roadmap", "phases", "milestones" ]
    if planning_keywords.any? { |keyword| message_lower.include?(keyword) }
      analysis[:type] = "complex_planning"
      analysis[:complexity_level] = 6
      analysis[:multi_step] = true
      analysis[:requires_tools] = true
      analysis[:list_management_scope] = "complex_workflow"
    end

    # Adjust based on conversation context
    if conversation_context[:current_list].present?
      analysis[:context_needed] << "current_list"
      analysis[:conversation_context_relevance] = "high"
      if analysis[:list_management_scope] == "none"
        analysis[:list_management_scope] = "single_list"
      end
    end

    # Check message length and complexity indicators
    if user_message.length > 100
      analysis[:complexity_level] += 1
    end

    if user_message.count(",") > 2 || user_message.count("and") > 1
      analysis[:multi_step] = true
      analysis[:complexity_level] += 1
    end

    # Cap complexity level
    analysis[:complexity_level] = [ analysis[:complexity_level], 10 ].min

    @logger.debug "Fallback analysis result: #{analysis}"
    analysis
  end
end
