class AgentToolExecutorService < ApplicationService
  TOOL_HANDLERS = {
    "read_list_items"    => :handle_read_list_items,
    "create_list_item"   => :handle_create_list_item,
    "update_list_item"   => :handle_update_list_item,
    "complete_list_item" => :handle_complete_list_item,
    "read_list"          => :handle_read_list,
    "web_search"         => :handle_web_search,
    "invoke_agent"       => :handle_invoke_agent,
    "poll_agent_run"     => :handle_poll_agent_run
  }.freeze

  def initialize(tool_call:, agent:, user:, organization:, invocable: nil)
    @tool_call = tool_call
    @agent = agent
    @user = user
    @organization = organization
    @invocable = invocable
    @function_name = tool_call.dig("function", "name")
    parse_arguments
  end

  def call
    handler = TOOL_HANDLERS[@function_name]
    return failure(message: "Unknown tool: #{@function_name}") unless handler

    # Verify agent has permission for this tool
    resource_type = tool_to_resource_type(@function_name)
    unless agent_has_permission_for?(resource_type, @function_name)
      return failure(message: "Agent does not have permission for #{@function_name}")
    end

    send(handler)
  rescue => e
    Rails.logger.error("AgentToolExecutor: #{e.class} - #{e.message}")
    failure(message: "Tool execution error: #{e.message}")
  end

  private

  def parse_arguments
    @arguments = JSON.parse(tool_call.dig("function", "arguments") || "{}")
  rescue JSON::ParserError
    @arguments = {}
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

    if run.completed?
      result[:result_summary] = run.result_summary
      result[:result_data] = run.result_data
    elsif run.failed?
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
