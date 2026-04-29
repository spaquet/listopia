class AgentTokenBudgetService < ApplicationService
  def initialize(agent:, estimated_tokens: 1000)
    @agent = agent
    @estimated_tokens = estimated_tokens
  end

  def call
    return failure(message: "Agent is not active") unless @agent.status_active?
    return failure(message: "Daily token limit reached") if daily_limit_exceeded?
    return failure(message: "Monthly token limit reached") if monthly_limit_exceeded?

    success(data: {
      remaining_today:   @agent.max_tokens_per_day - @agent.tokens_used_today,
      remaining_month:   @agent.max_tokens_per_month - @agent.tokens_used_this_month,
      can_run:           true
    })
  end

  private

  def daily_limit_exceeded?
    (@agent.tokens_used_today + @estimated_tokens) > @agent.max_tokens_per_day
  end

  def monthly_limit_exceeded?
    (@agent.tokens_used_this_month + @estimated_tokens) > @agent.max_tokens_per_month
  end
end
