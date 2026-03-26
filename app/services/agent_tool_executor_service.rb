class AgentToolExecutorService < ApplicationService
  TOOL_HANDLERS = {
    "ask_user"           => :handle_ask_user,
    "confirm_action"     => :handle_confirm_action,
    "read_list_items"    => :handle_read_list_items,
    "create_list"        => :handle_create_list,
    "create_list_item"   => :handle_create_list_item,
    "update_list_item"   => :handle_update_list_item,
    "complete_list_item" => :handle_complete_list_item,
    "read_list"          => :handle_read_list,
    "web_search"         => :handle_web_search,
    "invoke_agent"       => :handle_invoke_agent,
    "poll_agent_run"     => :handle_poll_agent_run
  }.freeze

  def initialize(tool_call:, agent:, user:, organization:, invocable: nil, run: nil)
    @tool_call = tool_call
    @agent = agent
    @user = user
    @organization = organization
    @invocable = invocable
    @run = run
    @function_name = tool_call.dig("function", "name")
    parse_arguments
  end

  def call
    handler = TOOL_HANDLERS[@function_name]
    return failure(message: "Unknown tool: #{@function_name}") unless handler

    # HITL tools (ask_user, confirm_action) don't need permission checks
    unless %w[ask_user confirm_action].include?(@function_name)
      # Verify agent has permission for this tool
      resource_type = tool_to_resource_type(@function_name)
      unless agent_has_permission_for?(resource_type, @function_name)
        return failure(message: "Agent does not have permission for #{@function_name}")
      end
    end

    send(handler)
  rescue => e
    Rails.logger.error("AgentToolExecutor: #{e.class} - #{e.message}")
    failure(message: "Tool execution error: #{e.message}")
  end

  private

  def parse_arguments
    args_string = @tool_call.dig("function", "arguments") || @tool_call.dig("arguments") || "{}"
    @arguments = JSON.parse(args_string)
  rescue JSON::ParserError
    @arguments = {}
  end

  def handle_ask_user
    return failure(message: "No run context available for HITL") unless @run

    question = @arguments["question"]
    options = @arguments["options"] || []

    return failure(message: "Question is required") unless question.present?

    # Create interaction record
    interaction = AiAgentInteraction.create!(
      ai_agent_run: @run,
      question: question,
      options: options,
      status: :pending,
      asked_at: Time.current
    )

    # Return success with interaction metadata (this will trigger run pause)
    success(data: {
      hitl_interaction_id: interaction.id,
      question: question,
      options: options,
      message: "User interaction created. Awaiting response."
    })
  end

  def handle_confirm_action
    return failure(message: "No run context available for HITL") unless @run

    description = @arguments["description"]
    expected_outcome = @arguments["expected_outcome"]

    return failure(message: "Description is required") unless description.present?

    # Create interaction record for confirmation
    interaction = AiAgentInteraction.create!(
      ai_agent_run: @run,
      question: "Do you approve the following action? #{description}",
      options: [ "Approve", "Reject" ],
      status: :pending,
      asked_at: Time.current
    )

    success(data: {
      hitl_interaction_id: interaction.id,
      description: description,
      expected_outcome: expected_outcome,
      message: "Confirmation requested. Awaiting user approval."
    })
  end

  def handle_read_list
    list = resolve_list
    return failure(message: "List not found or no access") unless list
    success(data: {
      id: list.id,
      title: list.title,
      description: list.description,
      item_count: list.list_items.count,
      status: list.status
    })
  end

  def handle_create_list
    title       = @arguments["title"]
    description = @arguments["description"] || ""
    category    = @arguments["category"] || "personal"
    items       = @arguments["items"] || []

    return failure(message: "Title is required") unless title.present?
    return failure(message: "At least one item is required") if items.empty?

    # Determine organization context
    org = @organization || (@invocable.is_a?(Chat) ? @invocable.organization : nil)
    return failure(message: "No organization context for list creation") unless org

    # Create list using ChatResourceCreatorService
    creator = ChatResourceCreatorService.new(
      resource_type: "list",
      parameters: {
        "title"       => title,
        "description" => description,
        "category"    => category
      },
      created_by_user: @user,
      created_in_organization: org
    )
    result = creator.call

    return failure(message: result.errors.join(", ")) if result.failure?

    list = result.data[:resource]
    items_created = 0

    # Add items to the list
    items.each do |item|
      title_str = item["title"].to_s.truncate(500)
      next if title_str.blank?

      list.list_items.create!(
        title: title_str,
        description: (item["description"] || "").to_s,
        priority: item["priority"] || "medium",
        organization: org,
        user: @user
      )
      items_created += 1
    end

    success(data: {
      list_id: list.id,
      list_title: list.title,
      items_created: items_created,
      message: "Created list '#{list.title}' with #{items_created} item(s)"
    })
  end

  def handle_read_list_items
    list = resolve_list
    return failure(message: "List not found") unless list

    items = list.list_items
    items = items.where(status: @arguments["status"]) if @arguments["status"].present?

    results = items.map do |item|
      {
        id: item.id,
        title: item.title,
        status: item.status,
        priority: item.priority,
        description: item.description,
        completed_at: item.completed_at
      }
    end

    success(data: { items: results, count: results.length })
  end

  def handle_create_list_item
    list = resolve_list
    return failure(message: "List not found or no write access") unless list

    item = list.list_items.build(
      title: @arguments["title"],
      description: @arguments["description"],
      priority: @arguments["priority"] || "medium",
      user: @user
    )

    if item.save
      success(data: { id: item.id, title: item.title, created: true })
    else
      failure(message: "Failed to create item: #{item.errors.full_messages.join(', ')}")
    end
  end

  def handle_update_list_item
    item = ListItem.find_by(id: @arguments["item_id"])
    return failure(message: "Item not found") unless item

    allowed_attrs = %w[title description status priority]
    attrs_to_update = @arguments.slice(*allowed_attrs)

    if item.update(attrs_to_update)
      success(data: { id: item.id, updated: true })
    else
      failure(message: "Failed to update item: #{item.errors.full_messages.join(', ')}")
    end
  end

  def handle_complete_list_item
    item = ListItem.find_by(id: @arguments["item_id"])
    return failure(message: "Item not found") unless item

    if item.update(status: :completed, completed_at: Time.current)
      success(data: { id: item.id, completed: true })
    else
      failure(message: "Failed to complete item")
    end
  end

  def handle_web_search
    # Stub: return empty results with note that it's not yet implemented
    success(data: {
      results: [],
      message: "Web search integration coming soon",
      query: @arguments["query"]
    })
  end

  def handle_invoke_agent
    agent_id = @arguments["agent_id"]
    sub_agent = AiAgent.kept.find_by(id: agent_id)
    return failure(message: "Sub-agent not found") unless sub_agent

    # Check if user can access this agent
    unless sub_agent.accessible_by?(@user)
      return failure(message: "You don't have access to this agent")
    end

    # Check orchestration depth (max 3)
    current_depth = current_run_depth + 1
    return failure(message: "Max orchestration depth (3) exceeded") if current_depth > 3

    # Create child run
    child_run = AiAgentRun.create!(
      ai_agent: sub_agent,
      user: @user,
      organization: @organization,
      invocable: @invocable,
      user_input: @arguments["user_input"],
      input_parameters: @arguments["parameters"] || {},
      parent_run_id: current_run_id,
      metadata: { depth: current_depth }
    )

    # Enqueue async job
    AgentRunJob.perform_later(child_run.id)

    success(data: {
      child_run_id: child_run.id,
      status: "pending",
      message: "Sub-agent invoked. Check status with poll_agent_run"
    })
  end

  def handle_poll_agent_run
    run_id = @arguments["run_id"]
    run = AiAgentRun.find_by(id: run_id)
    return failure(message: "Run not found") unless run

    # Check ownership
    return failure(message: "Not authorized to view this run") unless run.user == @user

    result = {
      id: run.id,
      status: run.status,
      steps_completed: run.steps_completed,
      steps_total: run.steps_total,
      progress_percent: run.progress_percent
    }

    if run.status_completed?
      result[:result_summary] = run.result_summary
      result[:result_data] = run.result_data
    elsif run.status_failed?
      result[:error_message] = run.error_message
    end

    success(data: result)
  end

  def resolve_list
    if @invocable.is_a?(List)
      @invocable
    elsif @arguments["list_id"].present?
      List.find_by(id: @arguments["list_id"])
    end
  end

  def agent_has_permission_for?(resource_type, tool_name)
    return true if resource_type.nil?  # some tools don't need resource checks

    resource = @agent.ai_agent_resources.enabled.find_by(resource_type: resource_type)
    return false unless resource

    write_tools = %w[create_list_item update_list_item complete_list_item]
    return resource.permission_read_only? || resource.permission_read_write? unless write_tools.include?(tool_name)
    resource.permission_write_only? || resource.permission_read_write?
  end

  def tool_to_resource_type(tool_name)
    {
      "read_list_items"    => "list",
      "create_list"        => "list",
      "create_list_item"   => "list",
      "read_list"          => "list",
      "update_list_item"   => "list_item",
      "complete_list_item" => "list_item",
      "web_search"         => "web_search",
      "invoke_agent"       => "agent",
      "poll_agent_run"     => nil
    }[tool_name]
  end

  def current_run_id
    # This is set via context; for now return nil
    # In the actual AgentExecutionService, this will be passed
    nil
  end

  def current_run_depth
    # This would be retrieved from the context; default to 0
    0
  end
end
