class AgentExecutionService < ApplicationService
  MAX_ITERATIONS = 30

  def initialize(agent_run:)
    @run = agent_run
    @agent = agent_run.ai_agent
    @user = agent_run.user
    @organization = agent_run.organization
  end

  def call
    # Budget check
    budget_check = AgentTokenBudgetService.call(agent: @agent, estimated_tokens: @agent.max_tokens_per_run)
    return failure(message: budget_check.message) if budget_check.failure?

    @run.start!
    broadcast_status_update

    messages = build_initial_messages
    iteration = 0
    max_iterations = [ @agent.max_steps, MAX_ITERATIONS ].min

    begin
      Timeout.timeout(@agent.timeout_seconds) do
        loop do
          iteration += 1
          break if iteration > max_iterations

          @run.reload
          break if @run.status_paused? || @run.status_cancelled?

          step = create_step(iteration, "llm_call", "Thinking...")
          step.start!
          broadcast_step_update(step)

          llm_response = call_llm(messages)
          return failure(message: llm_response.message) if llm_response.failure?

          response_data = llm_response.data
          step.complete!(output: { response: response_data[:content] })
          record_step_tokens(step, response_data)

          if response_data[:tool_calls].present?
            tool_result = execute_tool_calls(response_data[:tool_calls], iteration)

            # Check if any tool called for HITL (ask_user or confirm_action)
            if tool_result[:hitl_paused]
              @run.pause!
              broadcast_status_update
              return success(data: { run: @run, paused_for_interaction: true })
            end

            messages << { role: "assistant", content: response_data[:content], tool_calls: response_data[:tool_calls] }
            messages.concat(tool_result[:messages])
          else
            @run.complete!(summary: response_data[:content], data: { final_message: response_data[:content] })
            broadcast_completion
            return success(data: { run: @run })
          end
        end
      end

      @run.fail!("Maximum steps (#{@agent.max_steps}) exceeded")
      broadcast_status_update
      failure(message: "Agent exceeded maximum allowed steps")
    rescue Timeout::Error
      @run.fail!("Execution timed out after #{@agent.timeout_seconds}s")
      broadcast_status_update
      failure(message: "Timeout")
    rescue => e
      Rails.logger.error("AgentExecutionService: #{e.class} - #{e.message}\n#{e.backtrace.first(5).join("\n")}")
      @run.fail!(e.message)
      broadcast_status_update
      failure(message: e.message)
    end
  end

  private

  def build_initial_messages
    # Build context from instructions, body context, and pre-run answers
    context_result = AgentContextBuilder.call(run: @run)
    system_content = context_result.success? ? context_result.data[:context] : @agent.persona

    [
      { role: "system", content: system_content },
      { role: "user", content: @run.user_input }
    ]
  end

  def call_llm(messages)
    tools = AgentToolBuilder.tools_for_agent(@agent)

    begin
      Timeout.timeout(@agent.timeout_seconds) do
        response = make_llm_request(messages, tools)
        success(data: {
          content: response[:content],
          tool_calls: response[:tool_calls],
          input_tokens: response[:input_tokens].to_i,
          output_tokens: response[:output_tokens].to_i,
          thinking_tokens: response[:thinking_tokens].to_i
        })
      end
    rescue => e
      Rails.logger.error("LLM call failed: #{e.message}")
      failure(message: "LLM call failed: #{e.message}")
    end
  end

  def make_llm_request(messages, tools)
    # Use RubyLLM to call the specified model with tools
    llm_chat = RubyLLM::Chat.new(provider: :openai, model: @agent.model)

    # Add messages to the chat
    messages.each do |msg|
      llm_chat.add_message(role: msg[:role], content: msg[:content])
    end

    # Convert tool hashes to RubyLLM tool objects and inject into tools dict
    if tools.present?
      tools.each do |tool_hash|
        tool_wrapper = AgentToolWrapper.new(tool_hash)
        llm_chat.instance_variable_get(:@tools)[tool_wrapper.name.to_sym] = tool_wrapper
      end
    end

    # Call the LLM
    response = llm_chat.complete

    # Extract response content (defensive duck-typing for various response formats)
    content = extract_content(response)
    tool_calls = extract_tool_calls(response)
    input_tokens = extract_input_tokens(response)
    output_tokens = extract_output_tokens(response)
    thinking_tokens = extract_thinking_tokens(response)

    {
      content: content,
      tool_calls: tool_calls,
      input_tokens: input_tokens,
      output_tokens: output_tokens,
      thinking_tokens: thinking_tokens
    }
  end

  def extract_content(response)
    if response.respond_to?(:content)
      content = response.content
      content.respond_to?(:text) ? content.text : content.to_s
    elsif response.respond_to?(:text)
      response.text
    elsif response.respond_to?(:message)
      response.message
    elsif response.is_a?(Hash)
      response["content"] || response[:content] || response.to_s
    else
      response.to_s
    end
  end

  def extract_tool_calls(response)
    if response.respond_to?(:tool_calls)
      response.tool_calls || []
    elsif response.is_a?(Hash) && response["tool_calls"]
      response["tool_calls"]
    else
      []
    end
  end

  def extract_input_tokens(response)
    if response.respond_to?(:usage)
      response.usage.input_tokens rescue 0
    elsif response.is_a?(Hash)
      response["usage"]&.dig("prompt_tokens") || response["input_tokens"] || 0
    else
      0
    end
  end

  def extract_output_tokens(response)
    if response.respond_to?(:usage)
      response.usage.output_tokens rescue 0
    elsif response.is_a?(Hash)
      response["usage"]&.dig("completion_tokens") || response["output_tokens"] || 0
    else
      0
    end
  end

  def extract_thinking_tokens(response)
    if response.is_a?(Hash)
      response["usage"]&.dig("thinking_tokens") || 0
    else
      0
    end
  end

  def execute_tool_calls(tool_calls, iteration_base)
    hitl_paused = false
    messages = []

    tool_calls.each.with_index do |tool_call, i|
      step_num = "#{iteration_base}.#{i + 1}"
      tool_name = tool_call["function"]["name"] rescue tool_call["name"]

      step = create_step(step_num, "tool_call", "Calling #{tool_name}...")
      step.start!
      broadcast_step_update(step)

      result = AgentToolExecutorService.call(
        tool_call: tool_call,
        agent: @agent,
        user: @user,
        organization: @organization,
        invocable: @run.invocable,
        run: @run
      )

      if result.success?
        step.complete!(output: result.data)

        # Check if HITL was triggered (ask_user or confirm_action)
        if result.data[:hitl_interaction_id]
          hitl_paused = true
          break  # Don't process more tool calls if HITL is paused
        end

        messages << {
          role: "tool",
          tool_call_id: tool_call["id"],
          content: result.data.to_json
        }
      else
        step.fail!(result.message)
        messages << {
          role: "tool",
          tool_call_id: tool_call["id"],
          content: "Error: #{result.message}"
        }
      end
    end

    { messages: messages, hitl_paused: hitl_paused }
  end

  def create_step(number, type, title)
    @run.ai_agent_run_steps.create!(
      step_number: number.to_s,
      step_type: type,
      title: title,
      status: :pending
    )
  end

  def record_step_tokens(step, response_data)
    input_t = response_data[:input_tokens].to_i
    output_t = response_data[:output_tokens].to_i
    thinking_t = response_data[:thinking_tokens].to_i

    # Update step tokens (AiAgentRunStep only has input/output, not thinking)
    step.update_columns(
      input_tokens: input_t,
      output_tokens: output_t
    )

    # Update run tokens (AiAgentRun has all three)
    @run.increment!(:input_tokens, input_t)
    @run.increment!(:output_tokens, output_t)
    @run.increment!(:thinking_tokens, thinking_t)
    @run.increment!(:total_tokens, input_t + output_t)

    @agent.increment_token_usage!(input_t + output_t)
  end

  def broadcast_status_update
    Turbo::StreamsChannel.broadcast_replace_to(
      @run.turbo_channel,
      target: "agent-run-status-#{@run.id}",
      html: ApplicationController.render(
        partial: "ai_agents/run_status",
        locals: { run: @run }
      )
    )
  end

  def broadcast_step_update(step)
    Turbo::StreamsChannel.broadcast_append_to(
      @run.turbo_channel,
      target: "agent-run-steps-#{@run.id}",
      html: ApplicationController.render(
        partial: "ai_agents/run_step",
        locals: { step: step }
      )
    )

    Turbo::StreamsChannel.broadcast_replace_to(
      @run.turbo_channel,
      target: "agent-run-progress-#{@run.id}",
      html: ApplicationController.render(
        partial: "ai_agents/run_progress",
        locals: { run: @run }
      )
    )
  end

  def broadcast_completion
    Turbo::StreamsChannel.broadcast_replace_to(
      @run.turbo_channel,
      target: "agent-run-result-#{@run.id}",
      html: ApplicationController.render(
        partial: "ai_agents/run_result",
        locals: { run: @run }
      )
    )

    # Broadcast back to originating chat if this was a chat-triggered agent
    if @run.invocable.is_a?(Chat)
      broadcast_list_created_to_chat(@run.invocable)
    end
  end

  private

  def broadcast_list_created_to_chat(chat)
    # Extract list_id from the last create_list tool result
    list_tool_step = @run.ai_agent_run_steps
      .where(step_type: "tool_call", tool_name: "create_list")
      .order(created_at: :desc).first

    tool_output = list_tool_step&.tool_output || {}
    list_id = tool_output["list_id"]

    if list_id.present? && (list = List.find_by(id: list_id))
      # Create list_created message
      msg = Message.create_templated(
        chat: chat,
        template_type: "list_created",
        template_data: {
          list_id: list.id,
          list_title: list.title,
          items_count: list.list_items.count,
          run_id: @run.id
        }
      )
    else
      # Fallback: create text message if list not found
      msg = Message.create_assistant(
        chat: chat,
        content: @run.result_summary.presence || "List created successfully."
      )
    end

    # Replace the agent_running message (stored in run.input_parameters)
    chat_message_id = @run.input_parameters&.dig("chat_message_id")
    target = chat_message_id ? "message-#{chat_message_id}" : "chat-loading-#{chat.id}"

    Turbo::StreamsChannel.broadcast_replace_to(
      "chat_#{chat.id}",
      target: target,
      html: ApplicationController.render(
        partial: "chats/assistant_message_replacement",
        locals: { message: msg, chat_context: chat.build_ui_context }
      )
    )
  rescue => e
    Rails.logger.error("broadcast_list_created_to_chat failed: #{e.class} - #{e.message}")
  end
end
