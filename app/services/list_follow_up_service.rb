class ListFollowUpService < ApplicationService
  def initialize(list:, user:, organization:)
    @list = list
    @user = user
    @organization = organization
  end

  def call
    items_preview = @list.list_items.limit(15).pluck(:title).join(", ")

    prompt = <<~PROMPT
      A user just created this list: "#{@list.title}"
      List items (up to 15): #{items_preview}

      Generate relevant follow-up options in exactly 3 categories. Keep each option as a short action phrase (under 60 chars), written as if the user is sending a message.
      Return JSON only:
      {
        "questions": ["...", "..."],
        "suggestions": ["...", "..."],
        "actions": ["...", "..."]
      }

      Guidelines:
      - questions (2-3): things user could ask to improve/expand the list (e.g., "Add budget info to each item")
      - suggestions (2-3): proactive enhancements (e.g., "Group items by category", "Add priority levels")
      - actions (1-2): tasks an AI agent could perform (e.g., "Research prices for these items", "Find local providers")
    PROMPT

    llm_chat = RubyLLM::Chat.new(provider: :openai, model: "gpt-4.1-nano")
    llm_chat.add_message(role: "user", content: prompt)
    response = llm_chat.complete
    content = response.respond_to?(:content) ? response.content : response.to_s

    json_match = content.match(/\{[\s\S]*?\}/m)
    return failure(message: "No JSON found in response") unless json_match

    parsed = JSON.parse(json_match[0])
    success(data: {
      questions: Array(parsed["questions"]).first(3),
      suggestions: Array(parsed["suggestions"]).first(3),
      actions: Array(parsed["actions"]).first(2)
    })
  rescue JSON::ParserError => e
    failure(message: "JSON parse error: #{e.message}")
  rescue => e
    failure(message: "Follow-up service error: #{e.message}")
  end
end
