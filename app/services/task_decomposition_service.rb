# app/services/task_decomposition_service.rb

class TaskDecompositionService
  include ActiveModel::Model
  include ActiveModel::Attributes

  class DecompositionError < StandardError; end
  class DependencyError < StandardError; end

  attr_accessor :user, :context, :chat

  def initialize(user:, context: {}, chat:)
    @user = user
    @context = context
    @chat = chat # Now properly utilized for conversation context
    @logger = Rails.logger
    @context_manager = ConversationContextManager.new(user: user, chat: chat, current_context: context)
  end

  # Decompose a task into manageable steps and create linked lists
  def decompose_task(user_message, task_analysis)
    @logger.info "TaskDecompositionService: Starting task decomposition with chat context"

    begin
      # Get conversation context from the original chat
      conversation_context = extract_conversation_context

      # Use the original chat with enhanced context for decomposition
      enhanced_chat = prepare_chat_for_decomposition(conversation_context)

      # Build decomposition prompt with conversation context
      decomposition_prompt = build_decomposition_prompt(user_message, task_analysis, conversation_context)

      # Get decomposition from AI using the context-aware chat
      response = enhanced_chat.ask(decomposition_prompt)

      # Parse and validate the decomposition
      decomposition_data = parse_decomposition_response(response.content)

      # Create actual lists/tasks from decomposition with proper relationships
      created_lists = create_lists_from_decomposition(decomposition_data, user_message, task_analysis)

      # Build dependency map and create relationships
      dependency_map = build_dependency_map(decomposition_data[:steps])
      create_list_relationships(created_lists, dependency_map)

      # Validate dependencies
      validate_dependencies!(dependency_map)

      # Track the decomposition action
      track_decomposition_action(created_lists, user_message)

      {
        success: true,
        steps: decomposition_data[:steps],
        created_lists: created_lists,
        dependency_map: dependency_map,
        estimated_time: decomposition_data[:estimated_time],
        complexity_assessment: decomposition_data[:complexity_assessment],
        recommended_approach: decomposition_data[:recommended_approach],
        chat_context_used: conversation_context.present?
      }

    rescue => e
      @logger.error "Task decomposition failed: #{e.message}"
      @logger.error e.backtrace.join("\n")

      # Fallback to heuristic decomposition
      fallback_decomposition(user_message, task_analysis)
    end
  end

  # Decompose complex tasks with detailed workflow planning
  def decompose_complex_task(user_message, task_analysis)
    @logger.info "TaskDecompositionService: Starting complex task decomposition with chat context"

    begin
      # Get conversation context from the original chat
      conversation_context = extract_conversation_context

      # Use the original chat with workflow planning context
      enhanced_chat = prepare_chat_for_workflow_planning(conversation_context)

      # Build complex decomposition prompt
      complex_prompt = build_complex_decomposition_prompt(user_message, task_analysis, conversation_context)

      # Get detailed workflow plan
      response = enhanced_chat.ask(complex_prompt)

      # Parse complex workflow response
      workflow_data = parse_complex_workflow_response(response.content)

      # Create workflow plan with phases and actual lists
      workflow_plan = build_workflow_plan(workflow_data)
      created_lists = create_lists_from_workflow(workflow_plan, user_message, task_analysis)

      # Validate workflow integrity
      validate_workflow_plan!(workflow_plan)

      # Create complex relationships between workflow phases
      create_workflow_relationships(created_lists, workflow_plan)

      # Track the complex decomposition action
      track_workflow_decomposition_action(created_lists, workflow_plan, user_message)

      {
        success: true,
        workflow_plan: workflow_plan,
        created_lists: created_lists,
        total_phases: workflow_plan[:phases].length,
        estimated_duration: workflow_plan[:estimated_duration],
        critical_path: workflow_plan[:critical_path],
        risk_assessment: workflow_plan[:risk_assessment],
        chat_context_used: conversation_context.present?
      }

    rescue => e
      @logger.error "Complex task decomposition failed: #{e.message}"
      @logger.error e.backtrace.join("\n")

      # Fallback to simpler decomposition
      simple_result = decompose_task(user_message, task_analysis)
      convert_simple_to_complex_workflow(simple_result)
    end
  end

  # Track task progress using existing chat conversation and database relationships
  def track_task_progress(workflow_id)
    # Find the workflow by looking for lists created from this decomposition
    workflow_lists = find_workflow_lists(workflow_id)

    unless workflow_lists.any?
      return {
        success: false,
        error: "Workflow lists not found",
        workflow_id: workflow_id
      }
    end

    # Calculate progress based on actual list and item completion
    progress_data = calculate_actual_progress(workflow_lists)

    # Check for blockers by analyzing list relationships
    blockers = identify_actual_blockers(workflow_lists)

    # Generate progress report using chat context
    progress_report = generate_progress_report_with_context(workflow_lists, progress_data, blockers)

    {
      success: true,
      workflow_id: workflow_id,
      lists: workflow_lists.map { |list| { id: list.id, title: list.title, status: list.status } },
      progress: progress_data,
      blockers: blockers,
      report: progress_report,
      next_steps: identify_next_steps_from_relationships(workflow_lists)
    }
  end

  private

  # Extract relevant context from the ongoing conversation
  def extract_conversation_context
    return {} unless @chat

    context = {
      chat_id: @chat.id,
      conversation_history: @chat.messages.order(:created_at).limit(10).map do |msg|
        {
          role: msg.role,
          content: msg.content&.truncate(200),
          created_at: msg.created_at
        }
      end
    }

    # Add current page context if available
    if @context[:page].present?
      context[:current_page] = @context[:page]
    end

    # Add current list context if viewing a specific list
    if @context[:list_id].present?
      current_list = List.find_by(id: @context[:list_id])
      if current_list&.readable_by?(@user)
        context[:current_list] = {
          id: current_list.id,
          title: current_list.title,
          status: current_list.status,
          items_count: current_list.list_items.count,
          recent_items: current_list.list_items.order(:created_at).limit(5).map do |item|
            { title: item.title, completed: item.completed }
          end
        }
      end
    end

    # Add user's recent lists context
    context[:user_lists] = @user.lists.active.order(:updated_at).limit(3).map do |list|
      { id: list.id, title: list.title, status: list.status, items_count: list.list_items.count }
    end

    # Add conversation context manager insights
    context_summary = @context_manager.build_context_summary
    context[:ai_context] = context_summary

    context
  end

  # Prepare the original chat for decomposition with enhanced context
  def prepare_chat_for_decomposition(conversation_context)
    # Add system instructions that include conversation context
    decomposition_instructions = build_decomposition_system_instructions(conversation_context)

    # Use the original chat but enhance it with decomposition-specific instructions
    # This maintains conversation continuity while focusing on task decomposition
    @chat.with_instructions(decomposition_instructions, replace: false)

    @chat
  end

  # Prepare the original chat for complex workflow planning
  def prepare_chat_for_workflow_planning(conversation_context)
    # Add system instructions for workflow planning with context
    workflow_instructions = build_workflow_system_instructions(conversation_context)

    # Enhance the original chat with workflow-specific instructions
    @chat.with_instructions(workflow_instructions, replace: false)

    @chat
  end

  # Build system instructions that include conversation context
  def build_decomposition_system_instructions(conversation_context)
    instructions = [ "You are assisting with task decomposition. Consider the following conversation context:" ]

    if conversation_context[:current_list].present?
      list = conversation_context[:current_list]
      instructions << "The user is currently viewing '#{list[:title]}' which has #{list[:items_count]} items and is #{list[:status]}."
    end

    if conversation_context[:conversation_history].present?
      instructions << "Recent conversation context:"
      conversation_context[:conversation_history].each do |msg|
        instructions << "#{msg[:role].capitalize}: #{msg[:content]}"
      end
    end

    if conversation_context[:user_lists].any?
      list_titles = conversation_context[:user_lists].map { |l| l[:title] }
      instructions << "User's recent active lists: #{list_titles.join(', ')}"
    end

    instructions << "When decomposing tasks, consider this context and create practical, actionable steps that can be implemented as lists with items. Focus on creating clear dependencies and relationships between decomposed tasks."

    instructions.join("\n\n")
  end

  # Build workflow system instructions with context
  def build_workflow_system_instructions(conversation_context)
    instructions = [ "You are creating a complex workflow plan. Use the following context to inform your planning:" ]

    if conversation_context[:current_list].present?
      list = conversation_context[:current_list]
      instructions << "User is working with '#{list[:title]}' (#{list[:items_count]} items, status: #{list[:status]})"
    end

    if conversation_context[:ai_context]&.dig(:recent_actions).present?
      actions = conversation_context[:ai_context][:recent_actions]
      instructions << "Recent user actions: #{actions.keys.join(', ')}"
    end

    instructions << "Create workflow plans that can be implemented using the user's existing list management system. Consider dependencies, milestones, and practical execution steps."

    instructions.join("\n\n")
  end

  def build_decomposition_prompt(user_message, task_analysis, conversation_context)
    context_info = ""
    if conversation_context.present?
      if conversation_context[:current_list].present?
        context_info += "\nUser is currently working with: #{conversation_context[:current_list][:title]}"
      end
      if conversation_context[:user_lists].any?
        list_names = conversation_context[:user_lists].map { |l| l[:title] }
        context_info += "\nUser's active lists: #{list_names.join(', ')}"
      end
    end

    <<~PROMPT
      Break down this task into clear, actionable steps that can be implemented as lists and list items:

      User Request: "#{user_message}"

      #{context_info}

      Task Analysis Context:
      - Type: #{task_analysis[:type]}
      - Complexity Level: #{task_analysis[:complexity_level]}/10
      - Requires Tools: #{task_analysis[:requires_tools]}
      - Multi-step: #{task_analysis[:multi_step]}

      Please provide a JSON response with this structure:
      {
        "steps": [
          {
            "step_number": 1,
            "title": "Step title (will become list title)",
            "description": "Detailed description (will become list description)",
            "action_type": "tool_call|user_input|information_gathering|validation",
            "tool_needed": "tool_name or null",
            "dependencies": [step_numbers that must complete first],
            "estimated_time_minutes": number,
            "success_criteria": "How to know this step is complete",
            "list_items": [
              {
                "title": "Specific action item",
                "description": "Item details",
                "priority": "low|medium|high"
              }
            ]
          }
        ],
        "estimated_time": "total estimated time",
        "complexity_assessment": "assessment of difficulty",
        "recommended_approach": "suggested execution strategy"
      }

      Focus on creating practical steps that can be turned into manageable lists with specific action items.
      Consider the user's existing context when creating the decomposition.
      Only respond with valid JSON.
    PROMPT
  end

  def build_complex_decomposition_prompt(user_message, task_analysis, conversation_context)
    context_info = ""
    if conversation_context.present?
      if conversation_context[:current_list].present?
        context_info += "\nCurrent working context: #{conversation_context[:current_list][:title]} (#{conversation_context[:current_list][:status]})"
      end
      if conversation_context[:user_lists].any?
        context_info += "\nUser's active lists: #{conversation_context[:user_lists].map { |l| "#{l[:title]} (#{l[:items_count]} items)" }.join(', ')}"
      end
    end

    <<~PROMPT
      Create a detailed workflow plan for this complex task that can be implemented using lists and relationships:

      User Request: "#{user_message}"

      #{context_info}

      Task Analysis Context:
      - Type: #{task_analysis[:type]}
      - Complexity Level: #{task_analysis[:complexity_level]}/10
      - User Intent: #{task_analysis[:user_intent]}

      Please provide a comprehensive workflow plan as JSON:
      {
        "workflow_name": "descriptive name for this workflow",
        "phases": [
          {
            "phase_number": 1,
            "name": "Phase name (will become main list title)",
            "description": "What this phase accomplishes (list description)",
            "steps": [
              {
                "step_number": 1,
                "title": "Step title (will become list item)",
                "description": "Detailed description",
                "action_type": "tool_call|user_input|decision_point|validation",
                "tool_needed": "tool_name or null",
                "dependencies": [step references],
                "estimated_time_minutes": number,
                "success_criteria": "How to measure completion",
                "priority": "low|medium|high"
              }
            ],
            "phase_deliverables": ["what this phase produces"],
            "success_criteria": "how to know phase is complete"
          }
        ],
        "milestones": [
          {
            "name": "milestone name",
            "description": "what achievement this represents",
            "phase_dependencies": [phase numbers],
            "success_metrics": ["how to measure success"]
          }
        ],
        "estimated_duration": "total time estimate",
        "critical_path": ["key dependencies that could delay completion"],
        "risk_factors": ["potential issues and mitigation strategies"]
      }

      Design this workflow to work with the user's existing list management system.
      Consider how phases will relate to each other through list relationships.
      Only respond with valid JSON.
    PROMPT
  end

  # Create actual lists from decomposition steps
  def create_lists_from_decomposition(decomposition_data, user_message, task_analysis)
    created_lists = []

    # Create a parent list to group the decomposed tasks
    parent_list = @user.lists.create!(
      title: "#{task_analysis[:user_intent] || 'Task Decomposition'} - #{Time.current.strftime('%m/%d %H:%M')}",
      description: "Decomposed from: #{user_message}",
      status: :active,
      list_type: :professional,
      metadata: {
        source: "task_decomposition",
        original_message: user_message,
        decomposition_timestamp: Time.current.iso8601,
        chat_id: @chat.id,
        complexity_level: task_analysis[:complexity_level]
      }
    )

    created_lists << parent_list

    # Create lists for each decomposition step
    decomposition_data[:steps].each do |step|
      step_list = @user.lists.create!(
        title: step[:title],
        description: step[:description],
        status: :active,
        list_type: :professional,
        metadata: {
          source: "task_decomposition",
          parent_decomposition_id: parent_list.id,
          step_number: step[:step_number],
          estimated_time_minutes: step[:estimated_time_minutes],
          action_type: step[:action_type],
          tool_needed: step[:tool_needed],
          chat_id: @chat.id
        }
      )

      # Create relationship to parent list
      Relationship.create!(
        parent: parent_list,
        child: step_list,
        relationship_type: :parent_child,
        metadata: { step_number: step[:step_number] }
      )

      # Create list items if specified
      if step[:list_items].present?
        step[:list_items].each_with_index do |item, index|
          step_list.list_items.create!(
            title: item[:title],
            description: item[:description],
            priority: item[:priority] || "medium",
            position: index + 1
          )
        end
      else
        # Create a default item for the step
        step_list.list_items.create!(
          title: step[:title],
          description: step[:success_criteria],
          priority: "medium",
          position: 1
        )
      end

      created_lists << step_list
    end

    # Track the creation
    @context_manager.track_action(
      action: "task_decomposition_created",
      entity: parent_list,
      metadata: {
        total_steps: decomposition_data[:steps].count,
        estimated_time: decomposition_data[:estimated_time],
        complexity_assessment: decomposition_data[:complexity_assessment]
      }
    )

    created_lists
  end

  # Create lists from workflow plan
  def create_lists_from_workflow(workflow_plan, user_message, task_analysis)
    created_lists = []

    # Create a master workflow list
    master_list = @user.lists.create!(
      title: "#{workflow_plan[:workflow_name]} - Master Plan",
      description: "Complex workflow from: #{user_message}",
      status: :active,
      list_type: :professional,
      metadata: {
        source: "complex_workflow",
        original_message: user_message,
        workflow_timestamp: Time.current.iso8601,
        chat_id: @chat.id,
        total_phases: workflow_plan[:phases].length,
        estimated_duration: workflow_plan[:estimated_duration]
      }
    )

    created_lists << master_list

    # Create lists for each phase
    workflow_plan[:phases].each do |phase|
      phase_list = @user.lists.create!(
        title: phase[:name],
        description: phase[:description],
        status: :active,
        list_type: :professional,
        metadata: {
          source: "complex_workflow",
          master_workflow_id: master_list.id,
          phase_number: phase[:phase_number],
          phase_deliverables: phase[:phase_deliverables],
          success_criteria: phase[:success_criteria],
          chat_id: @chat.id
        }
      )

      # Create relationship to master list
      Relationship.create!(
        parent: master_list,
        child: phase_list,
        relationship_type: :parent_child,
        metadata: {
          phase_number: phase[:phase_number],
          phase_type: "workflow_phase"
        }
      )

      # Create list items for each step in the phase
      phase[:steps].each_with_index do |step, index|
        phase_list.list_items.create!(
          title: step[:title],
          description: step[:description],
          priority: step[:priority] || "medium",
          position: index + 1,
          metadata: {
            step_number: step[:step_number],
            action_type: step[:action_type],
            tool_needed: step[:tool_needed],
            estimated_time_minutes: step[:estimated_time_minutes],
            success_criteria: step[:success_criteria]
          }
        )
      end

      created_lists << phase_list
    end

    created_lists
  end

  # Create relationships based on dependency map
  def create_list_relationships(created_lists, dependency_map)
    # Skip the first list as it's the parent/master list
    step_lists = created_lists[1..]

    dependency_map.each do |step_number, dependencies|
      current_list = step_lists[step_number - 1] # Adjust for 0-based indexing
      next unless current_list

      dependencies.each do |dep_step_number|
        dependency_list = step_lists[dep_step_number - 1]
        next unless dependency_list

        # Create dependency relationship
        Relationship.create!(
          parent: dependency_list,
          child: current_list,
          relationship_type: :dependency_finish_to_start,
          metadata: {
            dependency_type: "task_decomposition",
            created_from_chat: @chat.id
          }
        )
      end
    end
  end

  # Create relationships for complex workflow
  def create_workflow_relationships(created_lists, workflow_plan)
    # Skip the master list
    phase_lists = created_lists[1..]

    # Create sequential dependencies between phases if not specified otherwise
    phase_lists.each_cons(2) do |current_phase, next_phase|
      Relationship.create!(
        parent: current_phase,
        child: next_phase,
        relationship_type: :dependency_finish_to_start,
        metadata: {
          dependency_type: "workflow_phase_sequence",
          created_from_chat: @chat.id
        }
      )
    end

    # Handle milestones by creating special relationships
    workflow_plan[:milestones]&.each do |milestone|
      milestone[:phase_dependencies]&.each do |phase_num|
        phase_list = phase_lists[phase_num - 1]
        next unless phase_list

        # Update phase metadata to include milestone info
        phase_metadata = phase_list.metadata || {}
        phase_metadata[:milestones] ||= []
        phase_metadata[:milestones] << {
          name: milestone[:name],
          description: milestone[:description],
          success_metrics: milestone[:success_metrics]
        }

        phase_list.update!(metadata: phase_metadata)
      end
    end
  end

  # Track decomposition action in conversation context
  def track_decomposition_action(created_lists, user_message)
    @context_manager.track_action(
      action: "task_decomposition_completed",
      entity: created_lists.first, # Parent list
      metadata: {
        user_message: user_message.truncate(200),
        total_lists_created: created_lists.count,
        total_items_created: created_lists.sum { |list| list.list_items.count },
        decomposition_method: "simple",
        chat_id: @chat.id
      }
    )
  end

  # Track workflow decomposition action
  def track_workflow_decomposition_action(created_lists, workflow_plan, user_message)
    @context_manager.track_action(
      action: "workflow_decomposition_completed",
      entity: created_lists.first, # Master workflow list
      metadata: {
        user_message: user_message.truncate(200),
        workflow_name: workflow_plan[:workflow_name],
        total_phases: workflow_plan[:phases].length,
        total_lists_created: created_lists.count,
        estimated_duration: workflow_plan[:estimated_duration],
        decomposition_method: "complex_workflow",
        chat_id: @chat.id
      }
    )
  end

  def parse_decomposition_response(response_content)
    json_content = clean_json_response(response_content)

    begin
      parsed = JSON.parse(json_content, symbolize_names: true)

      # Validate required structure
      unless parsed[:steps].is_a?(Array) && parsed[:steps].any?
        raise DecompositionError, "Decomposition must include steps array"
      end

      # Ensure required fields exist
      parsed[:estimated_time] ||= "Unknown"
      parsed[:complexity_assessment] ||= "Generated"
      parsed[:recommended_approach] ||= "sequential"

      parsed
    rescue JSON::ParserError => e
      @logger.error "Failed to parse decomposition JSON: #{e.message}"
      @logger.error "Response content: #{response_content}"
      raise DecompositionError, "Invalid JSON response from AI"
    end
  end

  def parse_complex_workflow_response(response_content)
    json_content = clean_json_response(response_content)

    begin
      parsed = JSON.parse(json_content, symbolize_names: true)

      # Validate workflow structure
      unless parsed[:phases].is_a?(Array) && parsed[:phases].any?
        raise DecompositionError, "Workflow must include phases array"
      end

      # Ensure required fields
      parsed[:workflow_name] ||= "Complex Workflow"
      parsed[:milestones] ||= []
      parsed[:estimated_duration] ||= "Unknown"
      parsed[:critical_path] ||= []
      parsed[:risk_factors] ||= []

      parsed
    rescue JSON::ParserError => e
      @logger.error "Failed to parse workflow JSON: #{e.message}"
      raise DecompositionError, "Invalid workflow JSON response from AI"
    end
  end

  def clean_json_response(response_content)
    # Remove markdown formatting and extra whitespace
    response_content.gsub(/```json\n?/, "").gsub(/```\n?/, "").strip
  end

  def build_dependency_map(steps)
    dependency_map = {}

    steps.each do |step|
      step_number = step[:step_number]
      dependencies = step[:dependencies] || []
      dependency_map[step_number] = dependencies
    end

    dependency_map
  end

  def validate_dependencies!(dependency_map)
    # Check for circular dependencies
    dependency_map.each do |step, dependencies|
      dependencies.each do |dep|
        if has_circular_dependency?(dependency_map, dep, step, [])
          raise DependencyError, "Circular dependency detected between steps #{step} and #{dep}"
        end
      end
    end
  end

  def has_circular_dependency?(dependency_map, current_step, target_step, visited)
    return true if current_step == target_step
    return false if visited.include?(current_step)

    visited << current_step
    dependencies = dependency_map[current_step] || []

    dependencies.any? do |dep|
      has_circular_dependency?(dependency_map, dep, target_step, visited.dup)
    end
  end

  # Find workflow lists by workflow ID (using metadata)
  def find_workflow_lists(workflow_id)
    # Look for lists created from decomposition with matching workflow_id or chat_id
    @user.lists.where(
      "metadata->>'chat_id' = ? OR metadata->>'parent_decomposition_id' = ? OR metadata->>'master_workflow_id' = ?",
      @chat.id.to_s, workflow_id.to_s, workflow_id.to_s
    )
  end

  # Calculate progress based on actual list completion
  def calculate_actual_progress(workflow_lists)
    total_lists = workflow_lists.count
    completed_lists = workflow_lists.count { |list| list.status == "completed" }

    total_items = workflow_lists.sum { |list| list.list_items.count }
    completed_items = workflow_lists.sum { |list| list.list_items.count(&:completed) }

    {
      total_lists: total_lists,
      completed_lists: completed_lists,
      list_completion_percentage: total_lists > 0 ? (completed_lists.to_f / total_lists * 100).round(1) : 0,
      total_items: total_items,
      completed_items: completed_items,
      item_completion_percentage: total_items > 0 ? (completed_items.to_f / total_items * 100).round(1) : 0,
      overall_progress: total_items > 0 ? (completed_items.to_f / total_items * 100).round(1) : 0
    }
  end

  # Identify blockers by analyzing relationships
  def identify_actual_blockers(workflow_lists)
    blockers = []

    workflow_lists.each do |list|
      # Check if this list is blocked by uncompleted dependencies
      blocking_dependencies = list.dependencies.joins(:parent).where.not(
        parent: { status: "completed" }
      )

      if blocking_dependencies.any?
        blocking_list_titles = blocking_dependencies.map { |dep| dep.parent.title }
        blockers << {
          blocked_list: list.title,
          blocked_by: blocking_list_titles,
          blocker_type: "dependency"
        }
      end
    end

    blockers
  end

  # Generate progress report using chat context
  def generate_progress_report_with_context(workflow_lists, progress_data, blockers)
    report = []

    report << "Progress Report for Task Decomposition"
    report << "Generated from chat: #{@chat.title}"
    report << ""
    report << "Overall Progress: #{progress_data[:overall_progress]}%"
    report << "Lists: #{progress_data[:completed_lists]}/#{progress_data[:total_lists]} completed"
    report << "Items: #{progress_data[:completed_items]}/#{progress_data[:total_items]} completed"

    if blockers.any?
      report << ""
      report << "Blockers identified:"
      blockers.each do |blocker|
        report << "- #{blocker[:blocked_list]} is blocked by: #{blocker[:blocked_by].join(', ')}"
      end
    end

    report << ""
    report << "Active Lists:"
    workflow_lists.each do |list|
      status_indicator = list.status == "completed" ? "✓" : "○"
      item_progress = "#{list.list_items.count(&:completed)}/#{list.list_items.count} items"
      report << "#{status_indicator} #{list.title} (#{item_progress})"
    end

    report.join("\n")
  end

  # Identify next steps based on relationships and current progress
  def identify_next_steps_from_relationships(workflow_lists)
    next_steps = []

    workflow_lists.each do |list|
      next if list.status == "completed"

      # Check if all dependencies are completed
      blocking_dependencies = list.dependencies.joins(:parent).where.not(
        parent: { status: "completed" }
      )

      if blocking_dependencies.empty?
        # This list is ready to work on
        incomplete_items = list.list_items.where(completed: false).limit(3)
        next_steps << {
          list_title: list.title,
          list_id: list.id,
          status: "ready",
          next_items: incomplete_items.map(&:title)
        }
      else
        # This list is blocked
        next_steps << {
          list_title: list.title,
          list_id: list.id,
          status: "blocked",
          blocked_by: blocking_dependencies.map { |dep| dep.parent.title }
        }
      end
    end

    # Sort so ready items come first
    next_steps.sort_by { |step| step[:status] == "ready" ? 0 : 1 }
  end

  def build_workflow_plan(workflow_data)
    {
      workflow_name: workflow_data[:workflow_name],
      phases: workflow_data[:phases] || [],
      milestones: workflow_data[:milestones] || [],
      estimated_duration: workflow_data[:estimated_duration],
      critical_path: workflow_data[:critical_path] || [],
      risk_assessment: workflow_data[:risk_factors] || []
    }
  end

  def validate_workflow_plan!(workflow_plan)
    unless workflow_plan[:phases].any?
      raise DecompositionError, "Workflow must have at least one phase"
    end

    workflow_plan[:phases].each_with_index do |phase, index|
      unless phase[:steps].any?
        raise DecompositionError, "Phase #{index + 1} must have at least one step"
      end
    end
  end

  def convert_simple_to_complex_workflow(simple_result)
    return simple_result unless simple_result[:success]

    # Convert the simple decomposition to complex workflow format
    phases = [ {
      phase_number: 1,
      name: "Task Execution Phase",
      description: "Execute all decomposed steps",
      steps: simple_result[:steps]
    } ]

    workflow_plan = {
      workflow_name: "Converted Simple Workflow",
      phases: phases,
      milestones: [],
      estimated_duration: simple_result[:estimated_time],
      critical_path: simple_result[:dependency_map].keys,
      risk_assessment: [ "Converted from simple decomposition" ]
    }

    simple_result.merge({
      workflow_plan: workflow_plan,
      total_phases: 1,
      estimated_duration: simple_result[:estimated_time],
      critical_path: simple_result[:dependency_map].keys,
      risk_assessment: workflow_plan[:risk_assessment]
    })
  end

  # Fallback decomposition using heuristics when AI fails
  def fallback_decomposition(user_message, task_analysis)
    @logger.info "Using fallback decomposition with conversation context"

    steps = []
    created_lists = []

    # Extract context for fallback
    conversation_context = extract_conversation_context

    case task_analysis[:type]
    when "task_management"
      steps = create_task_management_steps(user_message, conversation_context)
    when "complex_planning"
      steps = create_planning_steps(user_message, conversation_context)
    else
      steps = create_generic_steps(user_message, conversation_context)
    end

    # Create lists from fallback steps
    if steps.any?
      decomposition_data = { steps: steps }
      created_lists = create_lists_from_decomposition(decomposition_data, user_message, task_analysis)
    end

    {
      success: true,
      steps: steps,
      created_lists: created_lists,
      dependency_map: build_dependency_map(steps),
      estimated_time: "#{steps.length * 5} minutes",
      complexity_assessment: "Generated using fallback heuristics with conversation context",
      recommended_approach: "sequential execution",
      fallback_used: true,
      chat_context_used: conversation_context.present?
    }
  end

  def create_task_management_steps(user_message, conversation_context)
    steps = []
    current_list_context = conversation_context[:current_list]

    # Step 1: Requirements gathering
    steps << {
      step_number: 1,
      title: "Clarify Requirements",
      description: "Understand what needs to be created or managed",
      action_type: "information_gathering",
      tool_needed: nil,
      dependencies: [],
      estimated_time_minutes: 3,
      success_criteria: "Requirements are clearly defined",
      list_items: [
        {
          title: "Review original request: #{user_message.truncate(50)}",
          description: "Analyze the specific requirements",
          priority: "high"
        }
      ]
    }

    # Step 2: Context analysis (if we have current list context)
    if current_list_context.present?
      steps << {
        step_number: 2,
        title: "Analyze Current Context",
        description: "Review existing '#{current_list_context[:title]}' for relevant information",
        action_type: "information_gathering",
        tool_needed: "list_management_tool",
        dependencies: [ 1 ],
        estimated_time_minutes: 2,
        success_criteria: "Current context is understood and leveraged",
        list_items: [
          {
            title: "Review #{current_list_context[:title]}",
            description: "Check existing #{current_list_context[:items_count]} items for relevance",
            priority: "medium"
          }
        ]
      }
    end

    # Step 3: Implementation
    step_number = steps.count + 1
    dependencies = steps.count > 1 ? [ 1, 2 ] : [ 1 ]

    steps << {
      step_number: step_number,
      title: "Create or Update Lists",
      description: "Use list management tools to implement the requested changes",
      action_type: "tool_call",
      tool_needed: "list_management_tool",
      dependencies: dependencies,
      estimated_time_minutes: 5,
      success_criteria: "Lists and items are created successfully",
      list_items: [
        {
          title: "Create new list or update existing",
          description: "Implement the specific requirements from step 1",
          priority: "high"
        },
        {
          title: "Add requested items",
          description: "Create individual list items as specified",
          priority: "high"
        }
      ]
    }

    # Step 4: Validation
    steps << {
      step_number: step_number + 1,
      title: "Validate Results",
      description: "Confirm that the implementation meets the original requirements",
      action_type: "validation",
      tool_needed: nil,
      dependencies: [ step_number ],
      estimated_time_minutes: 2,
      success_criteria: "Implementation matches requirements and functions correctly",
      list_items: [
        {
          title: "Review created lists",
          description: "Ensure all requirements are addressed",
          priority: "medium"
        },
        {
          title: "Test functionality",
          description: "Verify that lists and items work as expected",
          priority: "medium"
        }
      ]
    }

    steps
  end

  def create_planning_steps(user_message, conversation_context)
    steps = []
    user_lists_context = conversation_context[:user_lists] || []

    # Step 1: Scope definition
    steps << {
      step_number: 1,
      title: "Define Planning Scope",
      description: "Establish boundaries and objectives for the planning task",
      action_type: "information_gathering",
      tool_needed: nil,
      dependencies: [],
      estimated_time_minutes: 5,
      success_criteria: "Planning scope and objectives are clearly defined",
      list_items: [
        {
          title: "Identify key objectives",
          description: "What specific outcomes are we planning for?",
          priority: "high"
        },
        {
          title: "Set planning timeframe",
          description: "Define the time horizon for this planning exercise",
          priority: "high"
        }
      ]
    }

    # Step 2: Resource assessment (using conversation context)
    resource_context = ""
    if user_lists_context.any?
      resource_context = "Consider existing lists: #{user_lists_context.map { |l| l[:title] }.join(', ')}"
    end

    steps << {
      step_number: 2,
      title: "Assess Available Resources",
      description: "Review current resources and constraints. #{resource_context}",
      action_type: "information_gathering",
      tool_needed: "list_management_tool",
      dependencies: [ 1 ],
      estimated_time_minutes: 4,
      success_criteria: "Current resources and constraints are documented",
      list_items: [
        {
          title: "Inventory existing resources",
          description: "What resources are currently available?",
          priority: "medium"
        },
        {
          title: "Identify constraints",
          description: "What limitations need to be considered?",
          priority: "medium"
        }
      ]
    }

    # Step 3: Plan development
    steps << {
      step_number: 3,
      title: "Develop Detailed Plan",
      description: "Create comprehensive plan with phases and milestones",
      action_type: "tool_call",
      tool_needed: "list_management_tool",
      dependencies: [ 1, 2 ],
      estimated_time_minutes: 8,
      success_criteria: "Detailed plan is created with clear phases and deliverables",
      list_items: [
        {
          title: "Create planning framework",
          description: "Establish main phases and structure",
          priority: "high"
        },
        {
          title: "Define milestones",
          description: "Set key checkpoints and deliverables",
          priority: "high"
        },
        {
          title: "Assign priorities and dependencies",
          description: "Establish execution order and importance levels",
          priority: "medium"
        }
      ]
    }

    # Step 4: Implementation planning
    steps << {
      step_number: 4,
      title: "Create Implementation Strategy",
      description: "Define how the plan will be executed and monitored",
      action_type: "tool_call",
      tool_needed: "list_management_tool",
      dependencies: [ 3 ],
      estimated_time_minutes: 5,
      success_criteria: "Implementation strategy is defined with clear next steps",
      list_items: [
        {
          title: "Define execution approach",
          description: "How will the plan be implemented?",
          priority: "high"
        },
        {
          title: "Set up monitoring system",
          description: "How will progress be tracked?",
          priority: "medium"
        },
        {
          title: "Identify success metrics",
          description: "How will success be measured?",
          priority: "medium"
        }
      ]
    }

    steps
  end

  def create_generic_steps(user_message, conversation_context)
    context_info = ""
    if conversation_context[:current_list].present?
      context_info = " in context of '#{conversation_context[:current_list][:title]}'"
    end

    [
      {
        step_number: 1,
        title: "Analyze Request",
        description: "Break down and understand the user's request#{context_info}",
        action_type: "information_gathering",
        tool_needed: nil,
        dependencies: [],
        estimated_time_minutes: 3,
        success_criteria: "Request is fully understood",
        list_items: [
          {
            title: "Review request: #{user_message.truncate(60)}",
            description: "Understand what the user is asking for",
            priority: "high"
          }
        ]
      },
      {
        step_number: 2,
        title: "Gather Information",
        description: "Collect any additional information needed to complete the request",
        action_type: "information_gathering",
        tool_needed: "list_management_tool",
        dependencies: [ 1 ],
        estimated_time_minutes: 4,
        success_criteria: "All necessary information is available",
        list_items: [
          {
            title: "Research requirements",
            description: "Identify what information is needed",
            priority: "medium"
          },
          {
            title: "Check existing resources",
            description: "See what's already available#{context_info}",
            priority: "medium"
          }
        ]
      },
      {
        step_number: 3,
        title: "Execute Solution",
        description: "Implement the requested action or provide the requested information",
        action_type: "tool_call",
        tool_needed: "list_management_tool",
        dependencies: [ 1, 2 ],
        estimated_time_minutes: 5,
        success_criteria: "User's request is fulfilled",
        list_items: [
          {
            title: "Implement solution",
            description: "Take the requested action",
            priority: "high"
          },
          {
            title: "Verify results",
            description: "Ensure the solution works correctly",
            priority: "medium"
          }
        ]
      }
    ]
  end
end
