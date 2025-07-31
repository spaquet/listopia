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
    @chat = chat
    @logger = Rails.logger
  end

  # Decompose a task into manageable steps using RubyLLM conversation flow
  def decompose_task(user_message, task_analysis)
    @logger.info "TaskDecompositionService: Starting task decomposition"

    begin
      # Create a focused decomposition chat
      decomposition_chat = create_decomposition_chat

      # Build intelligent decomposition prompt
      decomposition_prompt = build_decomposition_prompt(user_message, task_analysis)

      # Get decomposition from AI
      response = decomposition_chat.ask(decomposition_prompt)

      # Parse and validate the decomposition
      decomposition_data = parse_decomposition_response(response.content)

      # Build dependency map
      dependency_map = build_dependency_map(decomposition_data[:steps])

      # Validate dependencies
      validate_dependencies!(dependency_map)

      {
        success: true,
        steps: decomposition_data[:steps],
        dependency_map: dependency_map,
        estimated_time: decomposition_data[:estimated_time],
        complexity_assessment: decomposition_data[:complexity_assessment],
        recommended_approach: decomposition_data[:recommended_approach]
      }

    rescue => e
      @logger.error "Task decomposition failed: #{e.message}"

      # Fallback to heuristic decomposition
      fallback_decomposition(user_message, task_analysis)
    end
  end

  # Decompose complex tasks with detailed workflow planning
  def decompose_complex_task(user_message, task_analysis)
    @logger.info "TaskDecompositionService: Starting complex task decomposition"

    begin
      # Create advanced decomposition chat with workflow tools
      workflow_chat = create_workflow_chat

      # Build complex decomposition prompt
      complex_prompt = build_complex_decomposition_prompt(user_message, task_analysis)

      # Get detailed workflow plan
      response = workflow_chat.ask(complex_prompt)

      # Parse complex workflow response
      workflow_data = parse_complex_workflow_response(response.content)

      # Create workflow plan with phases and milestones
      workflow_plan = build_workflow_plan(workflow_data)

      # Validate workflow integrity
      validate_workflow_plan!(workflow_plan)

      {
        success: true,
        workflow_plan: workflow_plan,
        total_phases: workflow_plan[:phases].length,
        estimated_duration: workflow_plan[:estimated_duration],
        critical_path: workflow_plan[:critical_path],
        risk_assessment: workflow_plan[:risk_assessment]
      }

    rescue => e
      @logger.error "Complex task decomposition failed: #{e.message}"

      # Fallback to simpler decomposition
      simple_result = decompose_task(user_message, task_analysis)
      convert_simple_to_complex_workflow(simple_result)
    end
  end

  # Progressive task execution with user feedback integration
  def execute_progressive_task(workflow_plan, feedback_callback: nil)
    @logger.info "Starting progressive task execution"

    execution_results = {
      completed_phases: [],
      current_phase: nil,
      progress_percentage: 0,
      user_feedback: [],
      adaptive_changes: []
    }

    workflow_plan[:phases].each_with_index do |phase, index|
      @logger.info "Executing phase #{index + 1}: #{phase[:name]}"

      # Execute phase steps
      phase_result = execute_phase(phase, execution_results)

      # Record phase completion
      execution_results[:completed_phases] << {
        phase: phase,
        result: phase_result,
        completed_at: Time.current
      }

      # Update progress
      execution_results[:progress_percentage] = ((index + 1).to_f / workflow_plan[:phases].length * 100).round(1)

      # Get user feedback if callback provided
      if feedback_callback && phase_result[:needs_feedback]
        feedback = feedback_callback.call(phase_result)
        execution_results[:user_feedback] << feedback

        # Adapt workflow based on feedback
        if feedback[:requires_adaptation]
          adaptation = adapt_workflow_based_on_feedback(workflow_plan, feedback, index)
          execution_results[:adaptive_changes] << adaptation
        end
      end

      # Check for early termination conditions
      break if phase_result[:terminate_workflow]
    end

    execution_results
  end

  # Track task progress using RubyLLM conversation state
  def track_task_progress(workflow_id)
    workflow_state = load_workflow_state(workflow_id)

    unless workflow_state
      return {
        success: false,
        error: "Workflow not found",
        workflow_id: workflow_id
      }
    end

    # Calculate current progress
    progress_data = calculate_workflow_progress(workflow_state)

    # Check for blockers or issues
    blockers = identify_workflow_blockers(workflow_state)

    # Generate progress report
    progress_report = generate_progress_report(workflow_state, progress_data, blockers)

    {
      success: true,
      workflow_id: workflow_id,
      progress: progress_data,
      blockers: blockers,
      report: progress_report,
      next_steps: identify_next_steps(workflow_state)
    }
  end

  private

  def create_decomposition_chat
    # Create specialized chat for task decomposition
    decomposition_chat = @user.chats.build(
      title: "Task Decomposition - #{Time.current.to_i}",
      status: "decomposition"
    )

    decomposition_chat.model_id = Rails.application.config.mcp.model
    decomposition_chat
  end

  def create_workflow_chat
    # Create specialized chat for complex workflow planning
    workflow_chat = @user.chats.build(
      title: "Workflow Planning - #{Time.current.to_i}",
      status: "workflow_planning"
    )

    workflow_chat.model_id = Rails.application.config.mcp.model
    workflow_chat
  end

  def build_decomposition_prompt(user_message, task_analysis)
    <<~PROMPT
      Break down this task into clear, actionable steps:

      User Request: "#{user_message}"

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
            "title": "Step title",
            "description": "Detailed description",
            "action_type": "tool_call|user_input|information_gathering|validation",
            "tool_needed": "tool_name or null",
            "dependencies": [step_numbers that must complete first],
            "estimated_time_minutes": number,
            "success_criteria": "How to know this step is complete"
          }
        ],
        "estimated_time": "total estimated time",
        "complexity_assessment": "assessment of difficulty",
        "recommended_approach": "suggested execution strategy"
      }

      Focus on actionable steps that can be completed using available tools or clear user actions.
      Only respond with valid JSON.
    PROMPT
  end

  def build_complex_decomposition_prompt(user_message, task_analysis)
    <<~PROMPT
      Create a detailed workflow plan for this complex task:

      User Request: "#{user_message}"

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
            "name": "Phase name",
            "description": "What this phase accomplishes",
            "steps": [
              {
                "step_number": 1,
                "title": "Step title",
                "description": "Detailed description",
                "action_type": "tool_call|user_input|decision_point|validation",
                "tool_needed": "tool_name or null",
                "dependencies": [step references],
                "estimated_time_minutes": number,
                "success_criteria": "How to measure completion",
                "deliverables": ["what this step produces"]
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

      Only respond with valid JSON.
    PROMPT
  end

  def parse_decomposition_response(response_content)
    json_content = clean_json_response(response_content)

    begin
      parsed = JSON.parse(json_content, symbolize_names: true)

      # Validate required structure
      unless parsed[:steps].is_a?(Array)
        raise DecompositionError, "Steps must be an array"
      end

      # Ensure each step has required fields
      parsed[:steps].each_with_index do |step, index|
        step[:step_number] ||= index + 1
        step[:dependencies] ||= []
        step[:estimated_time_minutes] ||= 5
        step[:action_type] ||= "user_input"
      end

      parsed
    rescue JSON::ParserError => e
      @logger.error "Failed to parse decomposition JSON: #{e.message}"
      raise DecompositionError, "Invalid JSON response from decomposition"
    end
  end

  def parse_complex_workflow_response(response_content)
    json_content = clean_json_response(response_content)

    begin
      parsed = JSON.parse(json_content, symbolize_names: true)

      # Validate workflow structure
      unless parsed[:phases].is_a?(Array)
        raise DecompositionError, "Workflow phases must be an array"
      end

      # Ensure each phase has steps
      parsed[:phases].each do |phase|
        phase[:steps] ||= []
        phase[:phase_deliverables] ||= []
      end

      parsed[:milestones] ||= []
      parsed[:critical_path] ||= []
      parsed[:risk_factors] ||= []

      parsed
    rescue JSON::ParserError => e
      @logger.error "Failed to parse complex workflow JSON: #{e.message}"
      raise DecompositionError, "Invalid JSON response from workflow decomposition"
    end
  end

  def clean_json_response(response_content)
    response_content.gsub(/```json\n?/, "").gsub(/```\n?/, "").strip
  end

  def build_dependency_map(steps)
    dependency_map = {}

    steps.each do |step|
      step_id = step[:step_number]
      dependencies = step[:dependencies] || []

      dependency_map[step_id] = {
        step: step,
        depends_on: dependencies,
        blocks: []
      }
    end

    # Build reverse dependencies (what each step blocks)
    dependency_map.each do |step_id, step_data|
      step_data[:depends_on].each do |dependency_id|
        if dependency_map[dependency_id]
          dependency_map[dependency_id][:blocks] << step_id
        end
      end
    end

    dependency_map
  end

  def validate_dependencies!(dependency_map)
    # Check for circular dependencies
    dependency_map.each do |step_id, _|
      visited = Set.new
      check_circular_dependency(step_id, dependency_map, visited)
    end

    # Check for orphaned dependencies
    dependency_map.each do |step_id, step_data|
      step_data[:depends_on].each do |dependency_id|
        unless dependency_map.key?(dependency_id)
          raise DependencyError, "Step #{step_id} depends on non-existent step #{dependency_id}"
        end
      end
    end
  end

  def check_circular_dependency(step_id, dependency_map, visited, path = [])
    if path.include?(step_id)
      cycle_path = path[path.index(step_id)..-1] + [ step_id ]
      raise DependencyError, "Circular dependency detected: #{cycle_path.join(' -> ')}"
    end

    return if visited.include?(step_id)
    visited.add(step_id)

    step_data = dependency_map[step_id]
    return unless step_data

    step_data[:depends_on].each do |dependency_id|
      check_circular_dependency(dependency_id, dependency_map, visited, path + [ step_id ])
    end
  end

  def build_workflow_plan(workflow_data)
    {
      workflow_id: SecureRandom.uuid,
      name: workflow_data[:workflow_name],
      phases: workflow_data[:phases],
      milestones: workflow_data[:milestones],
      estimated_duration: workflow_data[:estimated_duration],
      critical_path: workflow_data[:critical_path],
      risk_assessment: workflow_data[:risk_factors],
      created_at: Time.current,
      status: "planned"
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

  # Fallback decomposition using heuristics
  def fallback_decomposition(user_message, task_analysis)
    @logger.info "Using fallback decomposition"

    steps = []

    case task_analysis[:type]
    when "task_management"
      steps = create_task_management_steps(user_message)
    when "complex_planning"
      steps = create_planning_steps(user_message)
    else
      steps = create_generic_steps(user_message)
    end

    {
      success: true,
      steps: steps,
      dependency_map: build_dependency_map(steps),
      estimated_time: "#{steps.length * 5} minutes",
      complexity_assessment: "Generated using fallback heuristics",
      recommended_approach: "sequential execution"
    }
  end

  def create_task_management_steps(user_message)
    [
      {
        step_number: 1,
        title: "Understand requirements",
        description: "Clarify what needs to be created or managed",
        action_type: "information_gathering",
        tool_needed: nil,
        dependencies: [],
        estimated_time_minutes: 2,
        success_criteria: "Requirements are clear"
      },
      {
        step_number: 2,
        title: "Create or update list",
        description: "Use list management tools to create the requested list",
        action_type: "tool_call",
        tool_needed: "list_management_tool",
        dependencies: [ 1 ],
        estimated_time_minutes: 3,
        success_criteria: "List is created successfully"
      },
      {
        step_number: 3,
        title: "Add items if requested",
        description: "Add any specific items mentioned in the request",
        action_type: "tool_call",
        tool_needed: "list_management_tool",
        dependencies: [ 2 ],
        estimated_time_minutes: 5,
        success_criteria: "All requested items are added"
      }
    ]
  end

  def create_planning_steps(user_message)
    [
      {
        step_number: 1,
        title: "Define planning scope",
        description: "Identify what needs to be planned and the key objectives",
        action_type: "information_gathering",
        tool_needed: nil,
        dependencies: [],
        estimated_time_minutes: 5,
        success_criteria: "Scope and objectives are defined"
      },
      {
        step_number: 2,
        title: "Break down into categories",
        description: "Organize planning elements into logical categories",
        action_type: "user_input",
        tool_needed: nil,
        dependencies: [ 1 ],
        estimated_time_minutes: 10,
        success_criteria: "Categories are identified"
      },
      {
        step_number: 3,
        title: "Create planning lists",
        description: "Create lists for each category or planning element",
        action_type: "tool_call",
        tool_needed: "list_management_tool",
        dependencies: [ 2 ],
        estimated_time_minutes: 15,
        success_criteria: "All planning lists are created"
      },
      {
        step_number: 4,
        title: "Populate with initial items",
        description: "Add initial items to each planning list",
        action_type: "tool_call",
        tool_needed: "list_management_tool",
        dependencies: [ 3 ],
        estimated_time_minutes: 20,
        success_criteria: "Lists have initial items"
      }
    ]
  end

  def create_generic_steps(user_message)
    [
      {
        step_number: 1,
        title: "Analyze request",
        description: "Understand what the user is asking for",
        action_type: "information_gathering",
        tool_needed: nil,
        dependencies: [],
        estimated_time_minutes: 3,
        success_criteria: "Request is understood"
      },
      {
        step_number: 2,
        title: "Provide response",
        description: "Give a helpful response to the user's request",
        action_type: "user_input",
        tool_needed: nil,
        dependencies: [ 1 ],
        estimated_time_minutes: 5,
        success_criteria: "User receives helpful response"
      }
    ]
  end

  def convert_simple_to_complex_workflow(simple_result)
    return { success: false, error: "Simple decomposition failed" } unless simple_result[:success]

    # Convert simple steps into a single-phase workflow
    workflow_plan = {
      workflow_id: SecureRandom.uuid,
      name: "Converted Workflow",
      phases: [
        {
          phase_number: 1,
          name: "Main Phase",
          description: "Primary execution phase",
          steps: simple_result[:steps],
          phase_deliverables: [ "Completed task" ],
          success_criteria: "All steps completed successfully"
        }
      ],
      milestones: [
        {
          name: "Task Completion",
          description: "All steps have been completed",
          phase_dependencies: [ 1 ],
          success_metrics: [ "All steps marked complete" ]
        }
      ],
      estimated_duration: simple_result[:estimated_time],
      critical_path: simple_result[:steps].map { |s| s[:step_number] },
      risk_assessment: [ "Converted from simple decomposition - limited risk analysis" ],
      created_at: Time.current,
      status: "planned"
    }

    {
      success: true,
      workflow_plan: workflow_plan,
      total_phases: 1,
      estimated_duration: simple_result[:estimated_time],
      critical_path: workflow_plan[:critical_path],
      risk_assessment: workflow_plan[:risk_assessment]
    }
  end

  def execute_phase(phase, execution_context)
    phase_results = {
      phase_name: phase[:name],
      completed_steps: [],
      failed_steps: [],
      needs_feedback: false,
      terminate_workflow: false
    }

    phase[:steps].each do |step|
      step_result = execute_step(step, execution_context)

      if step_result[:success]
        phase_results[:completed_steps] << step_result
      else
        phase_results[:failed_steps] << step_result

        # Determine if failure should terminate workflow
        if step_result[:critical_failure]
          phase_results[:terminate_workflow] = true
          break
        end
      end

      # Check if step requires user feedback
      if step_result[:requires_feedback]
        phase_results[:needs_feedback] = true
      end
    end

    phase_results
  end

  def execute_step(step, execution_context)
    case step[:action_type]
    when "tool_call"
      execute_tool_step(step, execution_context)
    when "user_input"
      execute_user_input_step(step, execution_context)
    when "information_gathering"
      execute_information_step(step, execution_context)
    when "validation"
      execute_validation_step(step, execution_context)
    when "decision_point"
      execute_decision_step(step, execution_context)
    else
      {
        success: false,
        error: "Unknown step action type: #{step[:action_type]}",
        step: step
      }
    end
  end

  def execute_tool_step(step, execution_context)
    return { success: false, error: "No tool specified" } unless step[:tool_needed]

    # This would integrate with the actual tool execution
    # For now, return a placeholder result
    {
      success: true,
      step: step,
      result: "Tool step executed (placeholder)",
      execution_time: step[:estimated_time_minutes],
      requires_feedback: false
    }
  end

  def execute_user_input_step(step, execution_context)
    {
      success: true,
      step: step,
      result: "User input step ready",
      requires_feedback: true,
      execution_time: 0
    }
  end

  def execute_information_step(step, execution_context)
    {
      success: true,
      step: step,
      result: "Information gathered",
      execution_time: step[:estimated_time_minutes],
      requires_feedback: false
    }
  end

  def execute_validation_step(step, execution_context)
    {
      success: true,
      step: step,
      result: "Validation completed",
      execution_time: step[:estimated_time_minutes],
      requires_feedback: false
    }
  end

  def execute_decision_step(step, execution_context)
    {
      success: true,
      step: step,
      result: "Decision point reached",
      requires_feedback: true,
      execution_time: 0
    }
  end

  def adapt_workflow_based_on_feedback(workflow_plan, feedback, current_phase_index)
    adaptation = {
      type: feedback[:adaptation_type],
      phase_affected: current_phase_index,
      changes_made: [],
      timestamp: Time.current
    }

    case feedback[:adaptation_type]
    when "add_steps"
      adaptation[:changes_made] = add_steps_to_workflow(workflow_plan, feedback[:new_steps], current_phase_index)
    when "modify_approach"
      adaptation[:changes_made] = modify_workflow_approach(workflow_plan, feedback[:new_approach], current_phase_index)
    when "skip_phase"
      adaptation[:changes_made] = skip_workflow_phase(workflow_plan, current_phase_index, feedback[:reason])
    end

    adaptation
  end

  def add_steps_to_workflow(workflow_plan, new_steps, phase_index)
    return [] unless new_steps.is_a?(Array)

    phase = workflow_plan[:phases][phase_index]
    return [] unless phase

    changes = []
    new_steps.each do |new_step|
      phase[:steps] << new_step
      changes << "Added step: #{new_step[:title]}"
    end

    changes
  end

  def modify_workflow_approach(workflow_plan, new_approach, phase_index)
    phase = workflow_plan[:phases][phase_index]
    return [] unless phase

    old_description = phase[:description]
    phase[:description] = new_approach[:description] if new_approach[:description]

    changes = [ "Modified phase approach from '#{old_description}' to '#{phase[:description]}'" ]

    if new_approach[:new_steps]
      phase[:steps] = new_approach[:new_steps]
      changes << "Replaced phase steps with new approach"
    end

    changes
  end

  def skip_workflow_phase(workflow_plan, phase_index, reason)
    phase = workflow_plan[:phases][phase_index]
    return [] unless phase

    phase[:status] = "skipped"
    phase[:skip_reason] = reason

    [ "Skipped phase '#{phase[:name]}' - Reason: #{reason}" ]
  end

  def load_workflow_state(workflow_id)
    # This would load from a persistent store (Redis, database, etc.)
    # For now, return nil to indicate not found
    Rails.cache.read("workflow_state:#{workflow_id}")
  end

  def calculate_workflow_progress(workflow_state)
    total_steps = 0
    completed_steps = 0

    workflow_state[:phases].each do |phase|
      phase[:steps].each do |step|
        total_steps += 1
        completed_steps += 1 if step[:status] == "completed"
      end
    end

    progress_percentage = total_steps > 0 ? (completed_steps.to_f / total_steps * 100).round(1) : 0

    {
      total_steps: total_steps,
      completed_steps: completed_steps,
      progress_percentage: progress_percentage,
      current_phase: find_current_phase(workflow_state),
      estimated_completion: calculate_estimated_completion(workflow_state)
    }
  end

  def identify_workflow_blockers(workflow_state)
    blockers = []

    workflow_state[:phases].each_with_index do |phase, phase_index|
      phase[:steps].each_with_index do |step, step_index|
        if step[:status] == "blocked"
          blockers << {
            phase_index: phase_index,
            step_index: step_index,
            step_title: step[:title],
            blocker_reason: step[:blocker_reason],
            blocked_since: step[:blocked_since]
          }
        end
      end
    end

    blockers
  end

  def generate_progress_report(workflow_state, progress_data, blockers)
    report = {
      workflow_name: workflow_state[:name],
      overall_progress: progress_data[:progress_percentage],
      current_status: determine_workflow_status(workflow_state),
      phases_summary: generate_phases_summary(workflow_state),
      blockers_count: blockers.length,
      estimated_completion: progress_data[:estimated_completion],
      generated_at: Time.current
    }

    if blockers.any?
      report[:urgent_blockers] = blockers.select { |b| b[:blocked_since] < 24.hours.ago }
    end

    report
  end

  def identify_next_steps(workflow_state)
    next_steps = []

    workflow_state[:phases].each do |phase|
      phase[:steps].each do |step|
        if step[:status] == "ready" || step[:status] == "waiting_for_dependencies"
          # Check if dependencies are met
          dependencies_met = step[:dependencies].all? do |dep_id|
            find_step_by_id(workflow_state, dep_id)&.dig(:status) == "completed"
          end

          if dependencies_met
            next_steps << {
              step_title: step[:title],
              step_description: step[:description],
              action_type: step[:action_type],
              estimated_time: step[:estimated_time_minutes],
              priority: calculate_step_priority(step, workflow_state)
            }
          end
        end
      end

      # Only return first few next steps to avoid overwhelming
      break if next_steps.length >= 3
    end

    next_steps
  end

  def find_current_phase(workflow_state)
    workflow_state[:phases].find { |phase| phase[:status] == "in_progress" } ||
    workflow_state[:phases].find { |phase| phase[:status] == "ready" }
  end

  def calculate_estimated_completion(workflow_state)
    remaining_time = 0

    workflow_state[:phases].each do |phase|
      phase[:steps].each do |step|
        unless step[:status] == "completed"
          remaining_time += step[:estimated_time_minutes] || 5
        end
      end
    end

    Time.current + remaining_time.minutes
  end

  def determine_workflow_status(workflow_state)
    if workflow_state[:phases].all? { |phase| phase[:status] == "completed" }
      "completed"
    elsif workflow_state[:phases].any? { |phase| phase[:status] == "in_progress" }
      "in_progress"
    elsif workflow_state[:phases].any? { |phase| phase[:status] == "blocked" }
      "blocked"
    else
      "ready"
    end
  end

  def generate_phases_summary(workflow_state)
    workflow_state[:phases].map do |phase|
      completed_steps = phase[:steps].count { |step| step[:status] == "completed" }
      total_steps = phase[:steps].length

      {
        name: phase[:name],
        status: phase[:status],
        progress: total_steps > 0 ? (completed_steps.to_f / total_steps * 100).round(1) : 0,
        completed_steps: completed_steps,
        total_steps: total_steps
      }
    end
  end

  def find_step_by_id(workflow_state, step_id)
    workflow_state[:phases].each do |phase|
      step = phase[:steps].find { |s| s[:step_number] == step_id }
      return step if step
    end
    nil
  end

  def calculate_step_priority(step, workflow_state)
    # Higher priority for steps on the critical path
    base_priority = 5

    critical_path = workflow_state[:critical_path] || []
    base_priority += 3 if critical_path.include?(step[:step_number])

    # Higher priority for steps that unblock others
    blocks_count = count_steps_blocked_by(step, workflow_state)
    base_priority += blocks_count * 2

    [ base_priority, 10 ].min
  end

  def count_steps_blocked_by(step, workflow_state)
    count = 0
    step_id = step[:step_number]

    workflow_state[:phases].each do |phase|
      phase[:steps].each do |other_step|
        if other_step[:dependencies]&.include?(step_id)
          count += 1
        end
      end
    end

    count
  end
end
