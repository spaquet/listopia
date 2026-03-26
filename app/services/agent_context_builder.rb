class AgentContextBuilder < ApplicationService
  def initialize(run:)
    @run = run
    @agent = run.ai_agent
    @organization = run.organization
  end

  def call
    parts = build_context_parts
    context = parts.compact.join("\n\n")
    success(data: { context: context })
  rescue => e
    Rails.logger.error("AgentContextBuilder failed: #{e.message}")
    failure(message: "Failed to build agent context: #{e.message}")
  end

  private

  def build_context_parts
    parts = []

    # 1. Prompt (core instruction)
    parts << @agent.prompt if @agent.prompt.present?

    # 2. Instructions (step-by-step SOP)
    if @agent.instructions.present?
      parts << "## Instructions\n#{@agent.instructions}"
    end

    # 3. Body context (auto-loaded context based on config)
    if @agent.body_context_config.is_a?(Hash) && @agent.body_context_config.present?
      body = load_body_context
      parts << "## Context\n#{body}" if body.present?
    end

    # 4. Pre-run answers (user's answers to pre_run_questions)
    if @run.pre_run_answers.is_a?(Hash) && @run.pre_run_answers.present?
      answers_text = format_pre_run_answers
      parts << "## Task Parameters\n#{answers_text}"
    end

    parts
  end

  def load_body_context
    config = @agent.body_context_config
    contexts = []

    # Load all lists in the organization
    if config["load"] == "all_lists"
      lists = @organization.lists.includes(:list_items).limit(50)
      contexts << format_lists(lists)
    end

    # Load the invocable resource (the thing the agent is working on)
    if config["load"] == "invocable" && @run.invocable.present?
      contexts << format_invocable(@run.invocable)
    end

    # Load recent agent runs (cross-run memory)
    if config["load"] == "recent_runs"
      limit = config["limit"].to_i || 5
      recent = @agent.ai_agent_runs
        .where.not(id: @run.id)
        .order(completed_at: :desc)
        .limit(limit)
        .select { |r| r.status_completed? }
      contexts << format_recent_runs(recent)
    end

    contexts.compact.join("\n\n")
  end

  def format_lists(lists)
    return "" if lists.empty?

    lines = [ "Available lists in your organization:" ]
    lists.each do |list|
      item_count = list.list_items.count
      completion = list.list_items.where(status: :completed).count
      lines << "- **#{list.title}** (#{completion}/#{item_count} completed)"
      lines << "  #{list.description}" if list.description.present?

      # Include a few items as context
      items = list.list_items.limit(5)
      items.each do |item|
        status_badge = item.status.to_s.upcase
        lines << "  - [#{status_badge}] #{item.title}"
      end
    end

    lines.join("\n")
  end

  def format_invocable(invocable)
    case invocable
    when List
      lines = [ "Target list: **#{invocable.title}**" ]
      lines << invocable.description if invocable.description.present?
      lines << ""
      lines << "Items:"
      invocable.list_items.limit(20).each do |item|
        lines << "- [#{item.status.upcase}] #{item.title} (priority: #{item.priority || 'none'})"
        lines << "  #{item.description}" if item.description.present?
      end
      lines.join("\n")
    when ListItem
      lines = [ "Target item: **#{invocable.title}**" ]
      lines << "Status: #{invocable.status.upcase}"
      lines << "Priority: #{invocable.priority}" if invocable.priority.present?
      lines << invocable.description if invocable.description.present?
      lines << ""
      lines << "Parent list: #{invocable.list.title}"
      lines.join("\n")
    else
      "Working with: #{invocable.class.name} #{invocable.id}"
    end
  end

  def format_recent_runs(runs)
    return "" if runs.empty?

    lines = [ "Recent execution history:" ]
    runs.each do |run|
      duration = run.duration_seconds || 0
      tokens = run.total_tokens || 0
      lines << "- #{run.created_at.strftime('%b %d %H:%M')}: #{run.result_summary&.truncate(100)}"
      lines << "  (#{duration}s, #{tokens} tokens)"
    end

    lines.join("\n")
  end

  def format_pre_run_answers
    answers = @run.pre_run_answers
    return "" if answers.empty?

    lines = []
    answers.each do |key, value|
      lines << "- **#{key}**: #{value}"
    end

    lines.join("\n")
  end
end
