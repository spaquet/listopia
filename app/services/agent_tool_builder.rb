module AgentToolBuilder
  TOOL_SPECS = {
    ask_user: {
      name: "ask_user",
      description: "Ask the user a question and pause execution until they respond. Use this when you need clarification or approval from the user.",
      parameters: {
        type: "object",
        properties: {
          question: {
            type: "string",
            description: "The question to ask the user"
          },
          options: {
            type: "array",
            items: { type: "string" },
            description: "Optional list of multiple-choice options for the user to select from"
          }
        },
        required: [ "question" ]
      }
    },
    confirm_action: {
      name: "confirm_action",
      description: "Ask the user to confirm before taking a significant action. Execution pauses until the user confirms or rejects.",
      parameters: {
        type: "object",
        properties: {
          description: {
            type: "string",
            description: "What action you want to perform"
          },
          expected_outcome: {
            type: "string",
            description: "What the user should expect if they approve"
          }
        },
        required: [ "description" ]
      }
    },
    read_list: {
      name: "read_list",
      description: "Get details about a list including its title, description, status, and item count",
      parameters: {
        type: "object",
        properties: {
          list_id: {
            type: "string",
            description: "The UUID of the list to read. Use the current invocable list if not specified."
          }
        },
        required: []
      }
    },
    read_list_items: {
      name: "read_list_items",
      description: "Get all items in a list with their details (title, description, status, priority)",
      parameters: {
        type: "object",
        properties: {
          list_id: {
            type: "string",
            description: "The UUID of the list. Use the current invocable list if not specified."
          },
          status: {
            type: "string",
            description: "Filter by status (pending, in_progress, completed). Omit to get all."
          }
        },
        required: []
      }
    },
    create_list_item: {
      name: "create_list_item",
      description: "Create a new item in a list",
      parameters: {
        type: "object",
        properties: {
          list_id: {
            type: "string",
            description: "The UUID of the list where to create the item."
          },
          title: {
            type: "string",
            description: "The title/name of the item",
            minLength: 1,
            maxLength: 500
          },
          description: {
            type: "string",
            description: "Optional description or details for the item"
          },
          priority: {
            type: "string",
            enum: [ "low", "medium", "high", "urgent" ],
            description: "Priority level for the item"
          }
        },
        required: [ "list_id", "title" ]
      }
    },
    update_list_item: {
      name: "update_list_item",
      description: "Update details of an existing list item",
      parameters: {
        type: "object",
        properties: {
          item_id: {
            type: "string",
            description: "The UUID of the item to update"
          },
          title: {
            type: "string",
            description: "New title for the item"
          },
          description: {
            type: "string",
            description: "New description for the item"
          },
          status: {
            type: "string",
            enum: [ "pending", "in_progress", "completed" ],
            description: "New status for the item"
          },
          priority: {
            type: "string",
            enum: [ "low", "medium", "high", "urgent" ],
            description: "New priority level"
          }
        },
        required: [ "item_id" ]
      }
    },
    complete_list_item: {
      name: "complete_list_item",
      description: "Mark a list item as completed",
      parameters: {
        type: "object",
        properties: {
          item_id: {
            type: "string",
            description: "The UUID of the item to complete"
          }
        },
        required: [ "item_id" ]
      }
    },
    invoke_agent: {
      name: "invoke_agent",
      description: "Invoke another AI agent as a sub-task (orchestration). The agent will run asynchronously and you can poll for results.",
      parameters: {
        type: "object",
        properties: {
          agent_id: {
            type: "string",
            description: "The UUID of the agent to invoke"
          },
          user_input: {
            type: "string",
            description: "What you want the sub-agent to do"
          },
          parameters: {
            type: "object",
            description: "Optional agent-specific parameters"
          }
        },
        required: [ "agent_id", "user_input" ]
      }
    },
    poll_agent_run: {
      name: "poll_agent_run",
      description: "Check the status of a running sub-agent. Use after calling invoke_agent to get results.",
      parameters: {
        type: "object",
        properties: {
          run_id: {
            type: "string",
            description: "The UUID of the agent run to check"
          }
        },
        required: [ "run_id" ]
      }
    },
    web_search: {
      name: "web_search",
      description: "Search the web for information (stub implementation - returns empty results)",
      parameters: {
        type: "object",
        properties: {
          query: {
            type: "string",
            description: "What to search for"
          }
        },
        required: [ "query" ]
      }
    }
  }.freeze

  def self.tools_for_agent(agent)
    # HITL tools are always available
    hitl_tools = [ TOOL_SPECS[:ask_user], TOOL_SPECS[:confirm_action] ]

    # Add tools for each resource
    resource_tools = agent.ai_agent_resources.enabled.map do |resource|
      tool_for_resource(resource)
    end.compact.flatten.uniq { |t| t[:name] }

    (hitl_tools + resource_tools).uniq { |t| t[:name] }
  end

  def self.tool_for_resource(resource)
    case resource.resource_type
    when "list"
      if resource.permission_read_only? || resource.permission_read_write?
        [ TOOL_SPECS[:read_list], TOOL_SPECS[:read_list_items] ]
      elsif resource.permission_write_only?
        [ TOOL_SPECS[:create_list_item] ]
      else
        []
      end
    when "list_item"
      tools = []
      if resource.permission_read_only? || resource.permission_read_write?
        tools << TOOL_SPECS[:read_list_items]
      end
      if resource.permission_write_only? || resource.permission_read_write?
        tools << TOOL_SPECS[:update_list_item]
        tools << TOOL_SPECS[:complete_list_item]
      end
      tools
    when "web_search"
      [ TOOL_SPECS[:web_search] ]
    when "agent"
      [ TOOL_SPECS[:invoke_agent], TOOL_SPECS[:poll_agent_run] ]
    else
      []
    end.flatten.uniq { |t| t[:name] }
  end

  def self.all_available_tools
    [
      TOOL_SPECS[:ask_user],
      TOOL_SPECS[:confirm_action],
      TOOL_SPECS[:read_list],
      TOOL_SPECS[:read_list_items],
      TOOL_SPECS[:create_list_item],
      TOOL_SPECS[:update_list_item],
      TOOL_SPECS[:complete_list_item],
      TOOL_SPECS[:invoke_agent],
      TOOL_SPECS[:poll_agent_run],
      TOOL_SPECS[:web_search]
    ]
  end
end
