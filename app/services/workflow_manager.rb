# app/services/workflow_manager.rb

class WorkflowManager
  include ActiveModel::Model
  include ActiveModel::Attributes

  class WorkflowError < StandardError; end
  class ExecutionError < StandardError; end

  attr_accessor :user, :context, :chat

  def initialize(user:, context: {}, chat:)
    @user = user
    @context = context
    @chat = chat
    @logger = Rails.logger
  end

  # Execute simple workflow with basic step management
  def execute_simple_workflow(steps:, context:)
    @logger.info "WorkflowManager: Executing simple workflow with #{steps.length} steps"

    workflow_id = SecureRandom.uuid
    execution_context = initialize_execution_context(workflow_id, steps, context)

    begin
      # Store workflow state for tracking
      store_workflow_state(execution_context)

      # Execute steps sequentially with dependency checking
      execution_results = execute_steps_with_dependencies(steps, execution_context)

      # Generate final result
      final_result = compile_workflow_results(execution_results, execution_context)

      # Update workflow state to completed
      mark_workflow_completed(workflow_id, final_result)

      {
        success: true,
        workflow_id: workflow_id,
        result: final_result,
        steps_completed: execution_results[:completed_steps].length,
        execution_time: execution_results[:total_time]
      }

    rescue => e
      @logger.error "Simple workflow execution failed: #{e.message}"

      # Mark workflow as failed but preserve partial results
      mark_workflow_failed(workflow_id, e.message, execution_results)

      {
        success: false,
        workflow_id: workflow_id,
        error: e.message,
        partial_results: execution_results,
        steps_completed: execution_results&.dig(:completed_steps)&.length || 0
      }
    end
  end

  # Execute complex workflow with phase management and progress tracking
  def execute_complex_workflow(workflow_plan:, context:)
    @logger.info "WorkflowManager: Executing complex workflow '#{workflow_plan[:name]}'"

    workflow_id = workflow_plan[:workflow_id]
    execution_context = initialize_complex_execution_context(workflow_plan, context)

    begin
      # Store initial workflow state
      store_workflow_state(execution_context)

      # Execute phases with milestone tracking
      phase_results = execute_phases_with_milestones(workflow_plan[:phases], execution_context)

      # Check milestone completion
      milestone_results = evaluate_milestones(workflow_plan[:milestones], phase_results)

      # Generate comprehensive result
      final_result = compile_complex_workflow_results(phase_results, milestone_results, execution_context)

      # Update workflow state
      mark_workflow_completed(workflow_id, final_result)

      {
        success: true,
        workflow_id: workflow_id,
        result: final_result,
        phases_completed: phase_results[:completed_phases].length,
        milestones_achieved: milestone_results[:achieved_milestones].length,
        progress: calculate_workflow_progress(execution_context)
      }

    rescue => e
      @logger.error "Complex workflow execution failed: #{e.message}"

      # Preserve all partial progress
      mark_workflow_failed(workflow_id, e.message, phase_results)

      {
        success: false,
        workflow_id: workflow_id,
        error: e.message,
        partial_results: phase_results,
        phases_completed: phase_results&.dig(:completed_phases)&.length || 0
      }
    end
  end

  # Create workflow templates for common use cases
  def create_workflow_template(template_type, parameters = {})
    case template_type
    when :event_planning
      create_event_planning_template(parameters)
    when :project_management
      create_project_management_template(parameters)
    when :travel_planning
      create_travel_planning_template(parameters)
    when :learning_curriculum
      create_learning_curriculum_template(parameters)
    else
      create_generic_workflow_template(parameters)
    end
  end

  # Step-by-step guidance through RubyLLM conversations
  def provide_step_guidance(workflow_id, current_step_id)
    workflow_state = load_workflow_state(workflow_id)
    return { success: false, error: "Workflow not found" } unless workflow_state

    current_step = find_step_in_workflow(workflow_state, current_step_id)
    return { success: false, error: "Step not found" } unless current_step

    # Create guidance chat focused on this specific step
    guidance_chat = create_guidance_chat(workflow_id, current_step)

    guidance_prompt = build_step_guidance_prompt(current_step, workflow_state)

    begin
      guidance_response = guidance_chat.ask(guidance_prompt)

      # Parse guidance response
      guidance_data = parse_guidance_response(guidance_response.content)

      {
        success: true,
        step: current_step,
        guidance: guidance_data[:guidance],
        next_actions: guidance_data[:next_actions],
        resources_needed: guidance_data[:resources_needed],
        success_criteria: guidance_data[:success_criteria]
      }

    rescue => e
      @logger.error "Step guidance generation failed: #{e.message}"

      # Fallback to basic guidance
      {
        success: true,
        step: current_step,
        guidance: generate_basic_step_guidance(current_step),
        next_actions: [ "Complete the step as described" ],
        resources_needed: current_step[:tool_needed] ? [ current_step[:tool_needed] ] : [],
        success_criteria: current_step[:success_criteria]
      }
    end
  end

  # Collaborative planning sessions with RubyLLM conversation management
  def start_collaborative_planning_session(planning_topic, collaborators = [])
    @logger.info "Starting collaborative planning session for: #{planning_topic}"

    session_id = SecureRandom.uuid

    # Create collaborative planning chat
    planning_chat = create_collaborative_chat(session_id, planning_topic)

    # Initialize planning session state
    session_state = {
      session_id: session_id,
      topic: planning_topic,
      collaborators: collaborators,
      planning_phases: [],
      decisions_made: [],
      action_items: [],
      status: "active",
      created_at: Time.current
    }

    # Store session state
    store_planning_session_state(session_state)

    # Generate initial planning structure
    initial_planning_prompt = build_collaborative_planning_prompt(planning_topic, collaborators)

    begin
      planning_response = planning_chat.ask(initial_planning_prompt)

      # Parse initial planning structure
      initial_structure = parse_collaborative_planning_response(planning_response.content)

      # Update session state with initial structure
      session_state[:planning_phases] = initial_structure[:phases]
      session_state[:suggested_timeline] = initial_structure[:timeline]

      store_planning_session_state(session_state)

      {
        success: true,
        session_id: session_id,
        initial_structure: initial_structure,
        planning_chat_id: planning_chat.id,
        next_phase: initial_structure[:phases]&.first
      }

    rescue => e
      @logger.error "Collaborative planning session initialization failed: #{e.message}"

      {
        success: false,
        error: e.message,
        session_id: session_id
      }
    end
  end

  # Plan validation using RubyLLM's context understanding
  def validate_workflow_plan(workflow_plan)
    @logger.info "Validating workflow plan: #{workflow_plan[:name]}"

    # Create validation chat
    validation_chat = create_validation_chat

    validation_prompt = build_plan_validation_prompt(workflow_plan)

    begin
      validation_response = validation_chat.ask(validation_prompt)

      # Parse validation results
      validation_results = parse_validation_response(validation_response.content)

      {
        success: true,
        validation_results: validation_results,
        is_valid: validation_results[:overall_score] >= 7,
        issues_found: validation_results[:issues],
        recommendations: validation_results[:recommendations],
        estimated_success_probability: validation_results[:success_probability]
      }

    rescue => e
      @logger.error "Plan validation failed: #{e.message}"

      # Fallback to basic validation
      basic_validation = perform_basic_plan_validation(workflow_plan)

      {
        success: true,
        validation_results: basic_validation,
        is_valid: basic_validation[:is_valid],
        validation_method: "fallback"
      }
    end
  end

  private

  def initialize_execution_context(workflow_id, steps, context)
    {
      workflow_id: workflow_id,
      workflow_type: "simple",
      steps: steps,
      context: context,
      started_at: Time.current,
      current_step_index: 0,
      completed_steps: [],
      failed_steps: [],
      execution_log: [],
      user_interactions: []
    }
  end

  def initialize_complex_execution_context(workflow_plan, context)
    {
      workflow_id: workflow_plan[:workflow_id],
      workflow_type: "complex",
      workflow_plan: workflow_plan,
      context: context,
      started_at: Time.current,
      current_phase_index: 0,
      completed_phases: [],
      failed_phases: [],
      milestone_progress: {},
      execution_log: [],
      user_interactions: [],
      adaptive_changes: []
    }
  end

  def execute_steps_with_dependencies(steps, execution_context)
    results = {
      completed_steps: [],
      failed_steps: [],
      skipped_steps: [],
      total_time: 0
    }

    # Create dependency graph for optimal execution order
    dependency_graph = build_step_dependency_graph(steps)
    execution_order = calculate_execution_order(dependency_graph)

    execution_order.each do |step_id|
      step = steps.find { |s| s[:step_number] == step_id }
      next unless step

      step_start_time = Time.current

      # Check if dependencies are satisfied
      unless dependencies_satisfied?(step, results[:completed_steps])
        results[:skipped_steps] << {
          step: step,
          reason: "Dependencies not satisfied",
          skipped_at: Time.current
        }
        next
      end

      # Execute the step
      step_result = execute_workflow_step(step, execution_context)

      step_execution_time = Time.current - step_start_time
      step_result[:execution_time] = step_execution_time
      results[:total_time] += step_execution_time

      if step_result[:success]
        results[:completed_steps] << step_result
        log_step_completion(execution_context, step, step_result)
      else
        results[:failed_steps] << step_result
        log_step_failure(execution_context, step, step_result)

        # Check if this is a critical step that should stop execution
        if step[:critical] || step_result[:critical_failure]
          break
        end
      end
    end

    results
  end

  def execute_phases_with_milestones(phases, execution_context)
    results = {
      completed_phases: [],
      failed_phases: [],
      milestone_achievements: [],
      total_execution_time: 0
    }

    phases.each_with_index do |phase, index|
      phase_start_time = Time.current

      @logger.info "Executing phase #{index + 1}: #{phase[:name]}"

      # Execute all steps in this phase
      phase_steps_result = execute_steps_with_dependencies(phase[:steps], execution_context)

      phase_execution_time = Time.current - phase_start_time
      results[:total_execution_time] += phase_execution_time

      phase_result = {
        phase: phase,
        steps_result: phase_steps_result,
        execution_time: phase_execution_time,
        completed_at: Time.current
      }

      if phase_steps_result[:failed_steps].empty?
        results[:completed_phases] << phase_result
        execution_context[:current_phase_index] = index + 1

        # Check for milestone achievements
        check_milestone_achievements_for_phase(phase, results, execution_context)
      else
        results[:failed_phases] << phase_result

        # Determine if workflow should continue or stop
        if phase[:critical] || phase_steps_result[:failed_steps].any? { |f| f[:critical_failure] }
          break
        end
      end
    end

    results
  end

  def execute_workflow_step(step, execution_context)
    case step[:action_type]
    when "tool_call"
      execute_tool_call_step(step, execution_context)
    when "user_input"
      execute_user_input_step(step, execution_context)
    when "information_gathering"
      execute_information_gathering_step(step, execution_context)
    when "validation"
      execute_validation_step(step, execution_context)
    when "decision_point"
      execute_decision_point_step(step, execution_context)
    else
      {
        success: false,
        error: "Unknown step action type: #{step[:action_type]}",
        step: step
      }
    end
  end

  def execute_tool_call_step(step, execution_context)
    return { success: false, error: "No tool specified" } unless step[:tool_needed]

    begin
      # Get the tool instance
      tool_instance = get_tool_instance(step[:tool_needed], execution_context)

      unless tool_instance
        return {
          success: false,
          error: "Tool not available: #{step[:tool_needed]}",
          step: step
        }
      end

      # Prepare tool arguments from step context
      tool_args = prepare_tool_arguments(step, execution_context)

      # Execute the tool
      tool_result = tool_instance.execute(**tool_args)

      {
        success: tool_result[:success] || false,
        result: tool_result,
        step: step,
        tool_used: step[:tool_needed],
        tool_args: tool_args
      }

    rescue => e
      @logger.error "Tool execution failed for step #{step[:step_number]}: #{e.message}"

      {
        success: false,
        error: "Tool execution failed: #{e.message}",
        step: step,
        tool_used: step[:tool_needed]
      }
    end
  end

  def execute_user_input_step(step, execution_context)
    # For user input steps, we mark them as needing user interaction
    # The actual execution happens when user provides the input

    {
      success: true,
      result: "User input step prepared",
      step: step,
      requires_user_input: true,
      input_prompt: step[:description],
      input_type: step[:input_type] || "text"
    }
  end

  def execute_information_gathering_step(step, execution_context)
    # Information gathering steps collect context and data

    gathered_info = {
      step_context: step,
      execution_context: execution_context[:context],
      timestamp: Time.current
    }

    # Add any specific information gathering logic here
    if step[:information_sources]
      gathered_info[:sources] = step[:information_sources]
    end

    {
      success: true,
      result: "Information gathered successfully",
      step: step,
      gathered_info: gathered_info
    }
  end

  def execute_validation_step(step, execution_context)
    # Validation steps check if previous steps meet success criteria

    validation_results = {
      step: step,
      validation_checks: [],
      overall_valid: true
    }

    # Check previous steps if this validation depends on them
    if step[:validates_steps]
      step[:validates_steps].each do |step_id|
        previous_step_result = find_completed_step(execution_context, step_id)

        if previous_step_result
          check_result = validate_step_result(previous_step_result, step[:validation_criteria])
          validation_results[:validation_checks] << check_result
          validation_results[:overall_valid] &&= check_result[:valid]
        else
          validation_results[:validation_checks] << {
            step_id: step_id,
            valid: false,
            reason: "Step not found or not completed"
          }
          validation_results[:overall_valid] = false
        end
      end
    end

    {
      success: validation_results[:overall_valid],
      result: validation_results,
      step: step
    }
  end

  def execute_decision_point_step(step, execution_context)
    # Decision point steps require user or AI-driven decisions

    decision_context = {
      step: step,
      available_options: step[:decision_options] || [],
      decision_criteria: step[:decision_criteria] || [],
      context_data: gather_decision_context(step, execution_context)
    }

    {
      success: true,
      result: "Decision point reached",
      step: step,
      requires_decision: true,
      decision_context: decision_context
    }
  end

  def get_tool_instance(tool_name, execution_context)
    # Create tool instances based on the tool name
    case tool_name
    when "list_management_tool"
      ListManagementTool.new(execution_context[:context][:user] || @user, execution_context[:context])
    else
      nil
    end
  end

  def prepare_tool_arguments(step, execution_context)
    base_args = step[:tool_arguments] || {}

    # Add context-specific arguments
    context_args = {
      context: execution_context[:context]
    }

    # Merge step-specific arguments with context
    base_args.merge(context_args)
  end

  def dependencies_satisfied?(step, completed_steps)
    return true unless step[:dependencies]&.any?

    completed_step_ids = completed_steps.map { |cs| cs[:step][:step_number] }

    step[:dependencies].all? { |dep_id| completed_step_ids.include?(dep_id) }
  end

  def build_step_dependency_graph(steps)
    graph = {}

    steps.each do |step|
      step_id = step[:step_number]
      dependencies = step[:dependencies] || []

      graph[step_id] = {
        step: step,
        depends_on: dependencies,
        blocks: []
      }
    end

    # Build reverse dependencies
    graph.each do |step_id, step_data|
      step_data[:depends_on].each do |dep_id|
        if graph[dep_id]
          graph[dep_id][:blocks] << step_id
        end
      end
    end

    graph
  end

  def calculate_execution_order(dependency_graph)
    # Topological sort to determine optimal execution order
    visited = Set.new
    temp_visited = Set.new
    execution_order = []

    dependency_graph.each_key do |step_id|
      unless visited.include?(step_id)
        visit_step(step_id, dependency_graph, visited, temp_visited, execution_order)
      end
    end

    execution_order.reverse
  end

  def visit_step(step_id, graph, visited, temp_visited, execution_order)
    return if visited.include?(step_id)

    if temp_visited.include?(step_id)
      @logger.warn "Circular dependency detected involving step #{step_id}"
      return
    end

    temp_visited.add(step_id)

    step_data = graph[step_id]
    if step_data
      step_data[:depends_on].each do |dep_id|
        visit_step(dep_id, graph, visited, temp_visited, execution_order)
      end
    end

    temp_visited.delete(step_id)
    visited.add(step_id)
    execution_order << step_id
  end

  def check_milestone_achievements_for_phase(phase, results, execution_context)
    workflow_plan = execution_context[:workflow_plan]
    return unless workflow_plan&.dig(:milestones)

    workflow_plan[:milestones].each do |milestone|
      if milestone[:phase_dependencies]&.include?(phase[:phase_number])
        # Check if milestone criteria are met
        if milestone_criteria_met?(milestone, results, execution_context)
          results[:milestone_achievements] << {
            milestone: milestone,
            achieved_at: Time.current,
            triggering_phase: phase[:name]
          }
        end
      end
    end
  end

  def milestone_criteria_met?(milestone, results, execution_context)
    # Check if milestone success metrics are satisfied
    return true unless milestone[:success_metrics]&.any?

    milestone[:success_metrics].all? do |metric|
      evaluate_success_metric(metric, results, execution_context)
    end
  end

  def evaluate_success_metric(metric, results, execution_context)
    case metric.downcase
    when /all steps completed/
      results[:completed_phases].any? &&
      results[:completed_phases].last[:steps_result][:failed_steps].empty?
    when /all phases completed/
      execution_context[:current_phase_index] >= execution_context[:workflow_plan][:phases].length
    else
      # Custom metric evaluation would go here
      true
    end
  end

  def evaluate_milestones(milestones, phase_results)
    achieved_milestones = []
    pending_milestones = []

    milestones.each do |milestone|
      if milestone_achieved_from_results?(milestone, phase_results)
        achieved_milestones << {
          milestone: milestone,
          achieved_at: Time.current
        }
      else
        pending_milestones << milestone
      end
    end

    {
      achieved_milestones: achieved_milestones,
      pending_milestones: pending_milestones,
      milestone_completion_rate: achieved_milestones.length.to_f / milestones.length
    }
  end

  def milestone_achieved_from_results?(milestone, phase_results)
    return false unless milestone[:phase_dependencies]&.any?

    required_phases = milestone[:phase_dependencies]
    completed_phase_numbers = phase_results[:completed_phases].map { |cp| cp[:phase][:phase_number] }

    required_phases.all? { |phase_num| completed_phase_numbers.include?(phase_num) }
  end

  def create_event_planning_template(parameters)
    {
      workflow_name: "Event Planning - #{parameters[:event_name] || 'Untitled Event'}",
      phases: [
        {
          phase_number: 1,
          name: "Initial Planning",
          description: "Define event scope, budget, and basic requirements",
          steps: [
            {
              step_number: 1,
              title: "Define event objectives",
              description: "Clarify the purpose and goals of the event",
              action_type: "user_input",
              estimated_time_minutes: 15,
              success_criteria: "Clear event objectives documented"
            },
            {
              step_number: 2,
              title: "Set budget parameters",
              description: "Establish budget limits and allocation priorities",
              action_type: "user_input",
              estimated_time_minutes: 10,
              success_criteria: "Budget framework established"
            },
            {
              step_number: 3,
              title: "Create planning checklist",
              description: "Generate comprehensive event planning checklist",
              action_type: "tool_call",
              tool_needed: "list_management_tool",
              dependencies: [ 1, 2 ],
              estimated_time_minutes: 5,
              success_criteria: "Planning checklist created"
            }
          ]
        },
        {
          phase_number: 2,
          name: "Venue and Logistics",
          description: "Secure venue and arrange core logistics",
          steps: [
            {
              step_number: 4,
              title: "Research venues",
              description: "Create list of potential venues with requirements",
              action_type: "tool_call",
              tool_needed: "list_management_tool",
              dependencies: [ 3 ],
              estimated_time_minutes: 20,
              success_criteria: "Venue options documented"
            },
            {
              step_number: 5,
              title: "Plan logistics timeline",
              description: "Create detailed timeline for event logistics",
              action_type: "tool_call",
              tool_needed: "list_management_tool",
              dependencies: [ 4 ],
              estimated_time_minutes: 15,
              success_criteria: "Logistics timeline created"
            }
          ]
        }
      ],
      milestones: [
        {
          name: "Planning Foundation Complete",
          description: "Basic event parameters and planning structure established",
          phase_dependencies: [ 1 ],
          success_metrics: [ "Planning checklist created", "Budget established" ]
        }
      ]
    }
  end

  def create_project_management_template(parameters)
    {
      workflow_name: "Project Management - #{parameters[:project_name] || 'Untitled Project'}",
      phases: [
        {
          phase_number: 1,
          name: "Project Initiation",
          description: "Define project scope, objectives, and initial planning",
          steps: [
            {
              step_number: 1,
              title: "Define project scope",
              description: "Clearly outline what the project will accomplish",
              action_type: "user_input",
              estimated_time_minutes: 20,
              success_criteria: "Project scope documented"
            },
            {
              step_number: 2,
              title: "Create project backlog",
              description: "Generate initial list of project tasks and requirements",
              action_type: "tool_call",
              tool_needed: "list_management_tool",
              dependencies: [ 1 ],
              estimated_time_minutes: 15,
              success_criteria: "Project backlog created"
            }
          ]
        }
      ],
      milestones: [
        {
          name: "Project Kickoff Complete",
          description: "Project is properly initiated with clear scope and backlog",
          phase_dependencies: [ 1 ],
          success_metrics: [ "Project backlog created" ]
        }
      ]
    }
  end

  def create_travel_planning_template(parameters)
    destination = parameters[:destination] || "Destination"

    {
      workflow_name: "Travel Planning - #{destination}",
      phases: [
        {
          phase_number: 1,
          name: "Trip Planning Foundation",
          description: "Establish basic trip parameters and requirements",
          steps: [
            {
              step_number: 1,
              title: "Define travel dates and duration",
              description: "Set specific travel dates and trip length",
              action_type: "user_input",
              estimated_time_minutes: 5,
              success_criteria: "Travel dates confirmed"
            },
            {
              step_number: 2,
              title: "Create travel checklist",
              description: "Generate comprehensive travel planning checklist",
              action_type: "tool_call",
              tool_needed: "list_management_tool",
              dependencies: [ 1 ],
              estimated_time_minutes: 10,
              success_criteria: "Travel checklist created"
            }
          ]
        }
      ],
      milestones: [
        {
          name: "Travel Foundation Set",
          description: "Basic travel parameters established",
          phase_dependencies: [ 1 ],
          success_metrics: [ "Travel checklist created" ]
        }
      ]
    }
  end

  def create_learning_curriculum_template(parameters)
    subject = parameters[:subject] || "Subject"

    {
      workflow_name: "Learning Curriculum - #{subject}",
      phases: [
        {
          phase_number: 1,
          name: "Curriculum Design",
          description: "Design learning objectives and curriculum structure",
          steps: [
            {
              step_number: 1,
              title: "Define learning objectives",
              description: "Establish what learners should achieve",
              action_type: "user_input",
              estimated_time_minutes: 15,
              success_criteria: "Learning objectives documented"
            },
            {
              step_number: 2,
              title: "Create study plan",
              description: "Generate structured study plan with topics",
              action_type: "tool_call",
              tool_needed: "list_management_tool",
              dependencies: [ 1 ],
              estimated_time_minutes: 20,
              success_criteria: "Study plan created"
            }
          ]
        }
      ],
      milestones: [
        {
          name: "Curriculum Framework Complete",
          description: "Learning structure and plan established",
          phase_dependencies: [ 1 ],
          success_metrics: [ "Study plan created" ]
        }
      ]
    }
  end

  def create_generic_workflow_template(parameters)
    {
      workflow_name: "Custom Workflow - #{parameters[:name] || 'Untitled'}",
      phases: [
        {
          phase_number: 1,
          name: "Initial Phase",
          description: "Primary workflow phase",
          steps: [
            {
              step_number: 1,
              title: "Define requirements",
              description: "Establish what needs to be accomplished",
              action_type: "user_input",
              estimated_time_minutes: 10,
              success_criteria: "Requirements defined"
            },
            {
              step_number: 2,
              title: "Create action plan",
              description: "Generate plan to achieve requirements",
              action_type: "tool_call",
              tool_needed: "list_management_tool",
              dependencies: [ 1 ],
              estimated_time_minutes: 15,
              success_criteria: "Action plan created"
            }
          ]
        }
      ],
      milestones: [
        {
          name: "Planning Complete",
          description: "Initial planning phase finished",
          phase_dependencies: [ 1 ],
          success_metrics: [ "Action plan created" ]
        }
      ]
    }
  end

  def create_guidance_chat(workflow_id, step)
    @user.chats.build(
      title: "Step Guidance - #{step[:title]}",
      status: "guidance"
    ).tap do |chat|
      chat.model_id = Rails.application.config.mcp.model
    end
  end

  def build_step_guidance_prompt(step, workflow_state)
    <<~PROMPT
      Provide detailed guidance for completing this workflow step:

      Step: #{step[:title]}
      Description: #{step[:description]}
      Action Type: #{step[:action_type]}
      Tool Needed: #{step[:tool_needed] || 'None'}
      Success Criteria: #{step[:success_criteria]}

      Workflow Context:
      - Workflow: #{workflow_state[:workflow_plan][:name]}
      - Current Phase: #{workflow_state[:current_phase_index] + 1}

      Please provide a JSON response with:
      {
        "guidance": "Step-by-step guidance for completing this step",
        "next_actions": ["specific action 1", "specific action 2"],
        "resources_needed": ["resource 1", "resource 2"],
        "success_criteria": "How to know when this step is complete",
        "common_pitfalls": ["pitfall 1", "pitfall 2"],
        "estimated_time": "time estimate"
      }

      Only respond with valid JSON.
    PROMPT
  end

  def parse_guidance_response(response_content)
    json_content = response_content.gsub(/```json\n?/, "").gsub(/```\n?/, "").strip

    begin
      JSON.parse(json_content, symbolize_names: true)
    rescue JSON::ParserError
      {
        guidance: "Complete the step as described in the workflow",
        next_actions: [ "Follow the step description" ],
        resources_needed: [],
        success_criteria: "Step completed successfully"
      }
    end
  end

  def generate_basic_step_guidance(step)
    case step[:action_type]
    when "tool_call"
      "Use the #{step[:tool_needed]} tool to complete this step. Make sure you have the necessary information ready before proceeding."
    when "user_input"
      "This step requires your input. Please provide the requested information clearly and completely."
    when "information_gathering"
      "Gather the necessary information as described. Take time to collect all relevant details."
    when "validation"
      "Review and validate the previous steps to ensure they meet the success criteria."
    when "decision_point"
      "This is a decision point. Consider the available options carefully before proceeding."
    else
      "Follow the step description to complete this task."
    end
  end

  def create_collaborative_chat(session_id, topic)
    @user.chats.build(
      title: "Collaborative Planning - #{topic}",
      status: "collaborative"
    ).tap do |chat|
      chat.model_id = Rails.application.config.mcp.model
    end
  end

  def build_collaborative_planning_prompt(topic, collaborators)
    <<~PROMPT
      Create a collaborative planning structure for: #{topic}

      Collaborators: #{collaborators.join(', ') if collaborators.any?}

      Please provide a JSON response with:
      {
        "phases": [
          {
            "name": "phase name",
            "description": "what this phase accomplishes",
            "collaborative_activities": ["activity 1", "activity 2"],
            "decisions_needed": ["decision 1", "decision 2"],
            "estimated_duration": "time estimate"
          }
        ],
        "timeline": "overall timeline estimate",
        "collaboration_points": ["key points where collaboration is crucial"],
        "decision_framework": "how decisions should be made"
      }

      Only respond with valid JSON.
    PROMPT
  end

  def parse_collaborative_planning_response(response_content)
    json_content = response_content.gsub(/```json\n?/, "").gsub(/```\n?/, "").strip

    begin
      JSON.parse(json_content, symbolize_names: true)
    rescue JSON::ParserError
      {
        phases: [
          {
            name: "Planning Phase",
            description: "Initial collaborative planning",
            collaborative_activities: [ "Discuss objectives", "Define scope" ],
            decisions_needed: [ "Approach selection" ],
            estimated_duration: "1-2 hours"
          }
        ],
        timeline: "To be determined",
        collaboration_points: [ "Regular check-ins" ],
        decision_framework: "Consensus-based decisions"
      }
    end
  end

  def create_validation_chat
    @user.chats.build(
      title: "Plan Validation",
      status: "validation"
    ).tap do |chat|
      chat.model_id = Rails.application.config.mcp.model
    end
  end

  def build_plan_validation_prompt(workflow_plan)
    <<~PROMPT
      Validate this workflow plan for feasibility and completeness:

      Plan: #{workflow_plan[:name]}
      Phases: #{workflow_plan[:phases].length}
      Estimated Duration: #{workflow_plan[:estimated_duration]}

      Phase Details:
      #{workflow_plan[:phases].map.with_index { |p, i| "#{i+1}. #{p[:name]} (#{p[:steps].length} steps)" }.join("\n")}

      Please provide a JSON validation assessment:
      {
        "overall_score": 1-10,
        "issues": ["issue 1", "issue 2"],
        "recommendations": ["recommendation 1", "recommendation 2"],
        "success_probability": 0.0-1.0,
        "time_assessment": "realistic|optimistic|pessimistic",
        "complexity_rating": "low|medium|high|very_high",
        "risk_factors": ["risk 1", "risk 2"]
      }

      Only respond with valid JSON.
    PROMPT
  end

  def parse_validation_response(response_content)
    json_content = response_content.gsub(/```json\n?/, "").gsub(/```\n?/, "").strip

    begin
      JSON.parse(json_content, symbolize_names: true)
    rescue JSON::ParserError
      perform_basic_plan_validation(nil)
    end
  end

  def perform_basic_plan_validation(workflow_plan)
    return { is_valid: false, issues: [ "No plan provided" ] } unless workflow_plan

    issues = []
    issues << "No phases defined" unless workflow_plan[:phases]&.any?
    issues << "Empty phases detected" if workflow_plan[:phases]&.any? { |p| p[:steps].nil? || p[:steps].empty? }

    {
      overall_score: issues.empty? ? 7 : 4,
      issues: issues,
      recommendations: issues.empty? ? [ "Plan looks reasonable" ] : [ "Address identified issues" ],
      success_probability: issues.empty? ? 0.8 : 0.5,
      time_assessment: "realistic",
      complexity_rating: "medium",
      risk_factors: issues,
      is_valid: issues.empty?
    }
  end

  def store_workflow_state(execution_context)
    Rails.cache.write(
      "workflow_state:#{execution_context[:workflow_id]}",
      execution_context,
      expires_in: 24.hours
    )
  end

  def store_planning_session_state(session_state)
    Rails.cache.write(
      "planning_session:#{session_state[:session_id]}",
      session_state,
      expires_in: 24.hours
    )
  end

  def load_workflow_state(workflow_id)
    Rails.cache.read("workflow_state:#{workflow_id}")
  end

  def compile_workflow_results(execution_results, execution_context)
    {
      workflow_id: execution_context[:workflow_id],
      completed_steps: execution_results[:completed_steps].length,
      total_steps: execution_context[:steps].length,
      success_rate: execution_results[:completed_steps].length.to_f / execution_context[:steps].length,
      execution_time: execution_results[:total_time],
      failed_steps: execution_results[:failed_steps].length,
      results_summary: generate_results_summary(execution_results)
    }
  end

  def compile_complex_workflow_results(phase_results, milestone_results, execution_context)
    {
      workflow_id: execution_context[:workflow_id],
      workflow_name: execution_context[:workflow_plan][:name],
      completed_phases: phase_results[:completed_phases].length,
      total_phases: execution_context[:workflow_plan][:phases].length,
      milestones_achieved: milestone_results[:achieved_milestones].length,
      total_milestones: execution_context[:workflow_plan][:milestones].length,
      execution_time: phase_results[:total_execution_time],
      success_rate: calculate_complex_success_rate(phase_results, milestone_results),
      results_summary: generate_complex_results_summary(phase_results, milestone_results)
    }
  end

  def generate_results_summary(execution_results)
    completed = execution_results[:completed_steps].length
    failed = execution_results[:failed_steps].length
    total = completed + failed

    "Completed #{completed}/#{total} steps successfully"
  end

  def generate_complex_results_summary(phase_results, milestone_results)
    phases_completed = phase_results[:completed_phases].length
    total_phases = phase_results[:completed_phases].length + phase_results[:failed_phases].length
    milestones_achieved = milestone_results[:achieved_milestones].length

    "Completed #{phases_completed}/#{total_phases} phases with #{milestones_achieved} milestones achieved"
  end

  def calculate_complex_success_rate(phase_results, milestone_results)
    phase_rate = phase_results[:completed_phases].length.to_f /
                 (phase_results[:completed_phases].length + phase_results[:failed_phases].length)

    milestone_rate = milestone_results[:milestone_completion_rate]

    (phase_rate + milestone_rate) / 2.0
  end

  def calculate_workflow_progress(execution_context)
    case execution_context[:workflow_type]
    when "simple"
      {
        current_step: execution_context[:current_step_index],
        total_steps: execution_context[:steps].length,
        progress_percentage: (execution_context[:current_step_index].to_f / execution_context[:steps].length * 100).round(1)
      }
    when "complex"
      {
        current_phase: execution_context[:current_phase_index],
        total_phases: execution_context[:workflow_plan][:phases].length,
        progress_percentage: (execution_context[:current_phase_index].to_f / execution_context[:workflow_plan][:phases].length * 100).round(1)
      }
    end
  end

  def mark_workflow_completed(workflow_id, results)
    workflow_state = load_workflow_state(workflow_id)
    return unless workflow_state

    workflow_state[:status] = "completed"
    workflow_state[:completed_at] = Time.current
    workflow_state[:final_results] = results

    store_workflow_state(workflow_state)
  end

  def mark_workflow_failed(workflow_id, error_message, partial_results)
    workflow_state = load_workflow_state(workflow_id)
    return unless workflow_state

    workflow_state[:status] = "failed"
    workflow_state[:failed_at] = Time.current
    workflow_state[:error_message] = error_message
    workflow_state[:partial_results] = partial_results

    store_workflow_state(workflow_state)
  end

  def log_step_completion(execution_context, step, result)
    execution_context[:execution_log] << {
      type: "step_completed",
      step_id: step[:step_number],
      step_title: step[:title],
      result: result,
      timestamp: Time.current
    }
  end

  def log_step_failure(execution_context, step, result)
    execution_context[:execution_log] << {
      type: "step_failed",
      step_id: step[:step_number],
      step_title: step[:title],
      error: result[:error],
      timestamp: Time.current
    }
  end

  def find_completed_step(execution_context, step_id)
    execution_context[:completed_steps].find { |cs| cs[:step][:step_number] == step_id }
  end

  def validate_step_result(step_result, validation_criteria)
    # Basic validation - can be extended with more sophisticated criteria
    {
      step_id: step_result[:step][:step_number],
      valid: step_result[:success] && validation_criteria_met?(step_result, validation_criteria),
      validation_details: validation_criteria
    }
  end

  def validation_criteria_met?(step_result, criteria)
    return true unless criteria&.any?

    # Simple criteria checking - extend as needed
    criteria.all? do |criterion|
      case criterion[:type]
      when "success_required"
        step_result[:success]
      when "result_contains"
        step_result[:result].to_s.include?(criterion[:value])
      else
        true
      end
    end
  end

  def gather_decision_context(step, execution_context)
    {
      previous_steps: execution_context[:completed_steps].map { |cs| cs[:step][:title] },
      workflow_progress: calculate_workflow_progress(execution_context),
      available_resources: execution_context[:context][:resources] || [],
      time_constraints: execution_context[:context][:time_constraints]
    }
  end

  def find_step_in_workflow(workflow_state, step_id)
    workflow_state[:workflow_plan][:phases].each do |phase|
      step = phase[:steps].find { |s| s[:step_number] == step_id }
      return step if step
    end
    nil
  end
end
