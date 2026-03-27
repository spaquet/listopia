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

          # If HITL was triggered inside RubyLLM's tool execution cycle, pause now
          if response_data[:hitl_triggered]
            step.complete!(output: { response: "Awaiting user interaction..." })
            record_step_tokens(step, response_data)
            @run.pause!
            broadcast_status_update
            broadcast_hitl_to_chat(response_data[:hitl_interaction])
            return success(data: { run: @run, paused_for_interaction: true })
          end

          step.complete!(output: { response: response_data[:content] })
          record_step_tokens(step, response_data)

          Rails.logger.debug("Iteration #{iteration}: Tool calls present? #{response_data[:tool_calls].present?}")
          Rails.logger.debug("Iteration #{iteration}: Tool calls count: #{response_data[:tool_calls]&.length || 0}")

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

    messages = [
      { role: "system", content: system_content },
      { role: "user", content: @run.user_input }
    ]

    # Re-inject answered HITL interactions so the LLM has context for the answers
    @run.ai_agent_interactions.where(status: :answered).order(created_at: :asc).each do |interaction|
      messages << { role: "assistant", content: "I asked: #{interaction.question}" }
      messages << { role: "user", content: interaction.answer }
    end

    messages
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

    # Log the system message and user input
    Rails.logger.debug("=== Agent Execution Start ===")
    Rails.logger.debug("Agent: #{@agent.name}")
    Rails.logger.debug("Model: #{@agent.model}")
    messages.each do |msg|
      Rails.logger.debug("Message role=#{msg[:role]}: #{msg[:content].to_s.truncate(500)}")
    end

    # Add messages to the chat
    messages.each do |msg|
      llm_chat.add_message(role: msg[:role], content: msg[:content])
    end

    # Register tools using RubyLLM's proper API (with_tool)
    # Note: Store agent context so tools can execute properly
    if tools.present?
      Rails.logger.debug("Registering #{tools.length} tools")
      tools.each do |tool_hash|
        tool_class = AgentToolWrapper.create_tool_class(
          tool_hash,
          agent: @agent,
          user: @user,
          organization: @organization,
          invocable: @run.invocable,
          run: @run
        )
        Rails.logger.debug("Registering tool: #{tool_hash[:name]} - #{tool_hash[:description]}")
        llm_chat.with_tool(tool_class)
      end
    else
      Rails.logger.debug("⚠️  NO TOOLS AVAILABLE - LLM will not be able to call any functions")
    end

    # Call the LLM
    response = llm_chat.complete

    Rails.logger.debug("=== LLM Response ===")
    Rails.logger.debug("LLM Response content: #{response.respond_to?(:content) ? response.content.inspect : 'N/A'}")
    Rails.logger.debug("Response class: #{response.class}")
    Rails.logger.debug("Response methods: #{response.respond_to?(:tool_calls) ? 'has tool_calls' : 'no tool_calls'}")

    # HITL Check: if ask_user or confirm_action was called internally by RubyLLM,
    # a pending AiAgentInteraction will exist. Signal the caller to pause.
    pending_interaction = @run.ai_agent_interactions.where(status: :pending).order(created_at: :desc).first
    if pending_interaction
      Rails.logger.debug("HITL Detected: Pending interaction found (#{pending_interaction.id})")
      return {
        content: nil,
        tool_calls: nil,
        hitl_triggered: true,
        hitl_interaction: pending_interaction,
        input_tokens: extract_input_tokens(response),
        output_tokens: extract_output_tokens(response),
        thinking_tokens: extract_thinking_tokens(response)
      }
    end

    # Extract response content (defensive duck-typing for various response formats)
    content = extract_content(response)
    tool_calls = extract_tool_calls(llm_chat)
    input_tokens = extract_input_tokens(response)
    output_tokens = extract_output_tokens(response)
    thinking_tokens = extract_thinking_tokens(response)

    Rails.logger.debug("Extracted Tool Calls: #{tool_calls.inspect}")

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

  def extract_tool_calls(llm_chat)
    # Extract tool calls from RubyLLM chat messages
    # Tool calls are stored on the messages themselves
    tool_calls = []

    begin
      if llm_chat.respond_to?(:messages) && llm_chat.messages.present?
        last_message = llm_chat.messages.last
        if last_message && last_message.respond_to?(:tool_calls)
          raw_tool_calls = last_message.tool_calls
          if raw_tool_calls.is_a?(Array)
            # Convert RubyLLM::ToolCall objects to the format expected by our system
            tool_calls = raw_tool_calls.map do |tc|
              tc_name = if tc.respond_to?(:name)
                         name_val = tc.name
                         name_val.is_a?(Array) ? name_val.first : name_val
                       elsif tc.respond_to?(:tool_name)
                         tc.tool_name
                       elsif tc.is_a?(Hash)
                         tc["name"] || tc[:name]
                       else
                         nil
                       end

              tc_args = if tc.respond_to?(:arguments)
                         args_val = tc.arguments
                         args_val.is_a?(String) ? args_val : (args_val&.to_json || "{}")
                       elsif tc.is_a?(Hash)
                         (tc["arguments"] || tc[:arguments] || {}).to_json
                       else
                         "{}"
                       end

              {
                id: (tc.respond_to?(:id) ? tc.id : nil) || SecureRandom.uuid,
                function: {
                  name: tc_name,
                  arguments: tc_args
                }
              }
            end.select { |tc| tc.dig(:function, :name).present? }
          end
        end
      end
    rescue => e
      Rails.logger.warn("Error extracting tool calls: #{e.message}")
    end

    tool_calls
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

  def broadcast_hitl_to_chat(interaction)
    return unless @run.invocable.is_a?(Chat)

    chat = @run.invocable
    chat_message_id = @run.input_parameters&.dig("chat_message_id")
    target = chat_message_id ? "message-#{chat_message_id}" : "chat-loading-#{chat.id}"
    channel = "chat_#{chat.id}"

    Rails.logger.debug("Turbo broadcast HITL:")
    Rails.logger.debug("  Channel: #{channel}")
    Rails.logger.debug("  Target: #{target}")
    Rails.logger.debug("  Interaction ID: #{interaction.id}")

    Turbo::StreamsChannel.broadcast_replace_to(
      channel,
      target: target,
      html: ApplicationController.render(
        partial: "chats/hitl_question",
        locals: { interaction: interaction, run: @run }
      )
    )

    Rails.logger.debug("✓ HITL broadcast sent successfully")
  rescue => e
    Rails.logger.error("broadcast_hitl_to_chat failed: #{e.class} - #{e.message}")
  end

  private

  def broadcast_list_created_to_chat(chat)
    # Extract list_id from agent run steps
    # First try to find a dedicated tool_call step (for newer versions)
    list_tool_step = @run.ai_agent_run_steps
      .where(step_type: "tool_call", tool_name: "create_list")
      .order(created_at: :desc).first

    # If not found, get the last llm_call step which may contain tool results
    list_tool_step ||= @run.ai_agent_run_steps
      .where(step_type: "llm_call")
      .order(created_at: :desc).first

    # Parse tool_output JSON
    tool_output = {}
    list_id = nil
    list_title = nil
    items_count = 0

    if list_tool_step&.tool_output.present?
      begin
        # Tool output might be nested in a "response" key
        output_data = if list_tool_step.tool_output.is_a?(String)
                        JSON.parse(list_tool_step.tool_output)
                      else
                        list_tool_step.tool_output
                      end

        # If response is a string (nested JSON), parse it
        if output_data["response"].is_a?(String)
          output_data = JSON.parse(output_data["response"])
        end

        tool_output = output_data
        list_id = tool_output["list_id"]
        list_title = tool_output["list_title"]
        items_count = tool_output["items_created"].to_i
      rescue JSON::ParserError => e
        Rails.logger.warn("Failed to parse tool_output: #{e.message}")
      end
    end

    Rails.logger.debug("broadcast_list_created_to_chat: list_id=#{list_id.inspect}, title=#{list_title.inspect}, items=#{items_count}")

    if list_id.present? && (list = List.find_by(id: list_id))
      # Create list_created templated message with button
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
    elsif list_id.present? && list_title.present?
      # Fallback: create templated message even if list lookup failed (might be scope issue)
      msg = Message.create_templated(
        chat: chat,
        template_type: "list_created",
        template_data: {
          list_id: list_id,
          list_title: list_title,
          items_count: items_count,
          run_id: @run.id
        }
      )
    else
      # Final fallback: text message with result summary
      fallback_content = @run.result_summary.presence || "✓ List created successfully!"
      msg = Message.create_assistant(
        chat: chat,
        content: fallback_content
      )
    end

    # Replace the agent_running message (stored in run.input_parameters)
    chat_message_id = @run.input_parameters&.dig("chat_message_id")
    target = chat_message_id ? "message-#{chat_message_id}" : "chat-loading-#{chat.id}"
    channel = "chat_#{chat.id}"

    Rails.logger.debug("Turbo broadcast:")
    Rails.logger.debug("  Channel: #{channel}")
    Rails.logger.debug("  Target: #{target}")
    Rails.logger.debug("  Message ID: #{msg.id}")
    Rails.logger.debug("  Message Template Type: #{msg.template_type}")

    Turbo::StreamsChannel.broadcast_replace_to(
      channel,
      target: target,
      html: ApplicationController.render(
        partial: "chats/assistant_message_replacement",
        locals: { message: msg, chat_context: chat.build_ui_context }
      )
    )

    Rails.logger.debug("✓ Broadcast sent successfully")
  rescue => e
    Rails.logger.error("broadcast_list_created_to_chat failed: #{e.class} - #{e.message}")
    Rails.logger.error(e.backtrace.first(5).join("\n"))
  end
end
