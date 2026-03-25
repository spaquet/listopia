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

    begin
      Timeout.timeout(@agent.timeout_seconds) do
        loop do
          iteration += 1
          break if iteration > [ @agent.max_steps, MAX_ITERATIONS ].min

          @run.reload
          break if @run.paused? || @run.cancelled?

          step = create_step(iteration, "llm_call", "Thinking...")
          step.start!
          broadcast_step_update(step)

          llm_response = call_llm(messages)
          return failure(message: llm_response.message) if llm_response.failure?

          response_data = llm_response.data
          step.complete!(output: { response: response_data[:content] })
          record_step_tokens(step, response_data)

          if response_data[:tool_calls].present?
            tool_results = execute_tool_calls(response_data[:tool_calls], iteration)
            messages << { role: "assistant", content: nil, tool_calls: response_data[:tool_calls] }
            messages.concat(tool_results)
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
    system_content = @agent.prompt
    system_content += "\n\nCurrent context: #{context_summary}" if @run.invocable.present?

    [
      { role: "system", content: system_content },
      { role: "user", content: @run.user_input }
    ]
  end

  def context_summary
    case @run.invocable_type
    when "List"
      list = @run.invocable
      "Working on list '#{list.title}' with #{list.list_items.count} items."
    when "ListItem"
      item = @run.invocable
      "Working on list item '#{item.title}' in list '#{item.list.title}'."
    when "Chat"
      "Invoked from chat context."
    else
      ""
    end
  end

  def call_llm(messages)
    tools = AgentToolBuilder.tools_for_agent(@agent)

    begin
      # Using RubyLLM - simulated as the exact API depends on the library version
      # This assumes a standard OpenAI-compatible interface
      Timeout.timeout(@agent.timeout_seconds) do
        response = make_llm_request(messages, tools)
        success(data: {
          content: response[:content],
          tool_calls: response[:tool_calls],
          input_tokens: response[:input_tokens].to_i,
          output_tokens: response[:output_tokens].to_i
        })
      end
    rescue => e
      failure(message: "LLM call failed: #{e.message}")
    end
  end

  def make_llm_request(messages, tools)
    # Placeholder: actual RubyLLM integration
    # In production, this would call: RubyLLM::Chat.new(...).complete(messages, tools)
    # For now, return a stub response
    {
      content: "I would help with this task, but the LLM integration needs configuration.",
      tool_calls: [],
      input_tokens: 0,
      output_tokens: 0
    }
  end

  def execute_tool_calls(tool_calls, iteration_base)
    tool_calls.map.with_index do |tool_call, i|
      step_num = "#{iteration_base}.#{i + 1}"
      step = create_step(step_num, "tool_call", "Calling #{tool_call['function']['name']}...")
      step.start!
      broadcast_step_update(step)

      result = AgentToolExecutorService.call(
        tool_call: tool_call,
        agent: @agent,
        user: @user,
        organization: @organization,
        invocable: @run.invocable
      )

      if result.success?
        step.complete!(output: result.data)
        { role: "tool", tool_call_id: tool_call["id"], content: result.data.to_json }
      else
        step.fail!(result.message)
        { role: "tool", tool_call_id: tool_call["id"], content: "Error: #{result.message}" }
      end
    end
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
    step.update_columns(input_tokens: input_t, output_tokens: output_t)
    @run.increment!(:input_tokens, input_t)
    @run.increment!(:output_tokens, output_t)
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
  end
end
