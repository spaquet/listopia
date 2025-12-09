# app/services/ai_intent_router_service.rb
#
# Uses the LLM to detect user intent in natural language
# Works with any language and phrasing variations
# More accurate than rule-based routing

class AiIntentRouterService < ApplicationService
  def initialize(user_message:, chat:, user:, organization:)
    @user_message = user_message
    @chat = chat
    @user = user
    @organization = organization
  end

  def call
    # Extract intent using LLM
    intent = detect_intent_with_llm

    if intent.present?
      success(data: intent)
    else
      success(data: { action: :chat, intent: :general_question })
    end
  rescue StandardError => e
    Rails.logger.error("Intent detection failed: #{e.message}")
    # Graceful fallback to chat mode
    success(data: { action: :chat, intent: :general_question })
  end

  private

  # Use LLM to detect intent from user message
  def detect_intent_with_llm
    system_prompt = <<~PROMPT
      You are an intent classifier for a task management application.
      Analyze the user's message and classify their intent.

      Respond with ONLY a JSON object (no other text) in this exact format:
      {"intent": "intent_type", "action": "action_type", "description": "brief description"}

      Available intents and actions:
      - Intent: "navigate_to_page", Action: "navigate", Description: Page to navigate to
        Examples: "show users", "list teams", "show me active users", "who's in this org", etc.

      - Intent: "create_resource", Action: "chat", Description: User wants to create something
        Examples: "create user", "add team", "new list", etc.

      - Intent: "search_data", Action: "chat", Description: User wants to search/find something
        Examples: "find lists about budget", "search for users", etc.

      - Intent: "manage_resource", Action: "chat", Description: User wants to update/delete
        Examples: "update user role", "suspend user", "change team name", etc.

      - Intent: "general_question", Action: "chat", Description: General question/conversation
        Examples: "how do I?", "what is?", "tell me about", casual questions, etc.

      Classify based on the user's clear intent, regardless of language or phrasing.

      User message: "#{@user_message.content}"
    PROMPT

    response = call_llm_for_classification(system_prompt)
    parse_intent_response(response)
  end

  # Call LLM for classification
  def call_llm_for_classification(system_prompt)
    llm_chat = RubyLLM::Chat.new(
      provider: :openai,
      model: "gpt-4o-mini"
    )

    llm_chat.temperature = 0.3 if llm_chat.respond_to?(:temperature=)
    llm_chat.add_message(role: "system", content: system_prompt)
    llm_chat.add_message(role: "user", content: "Classify the intent.")

    response = llm_chat.complete
    extract_response_content(response)
  rescue => e
    Rails.logger.error("LLM classification failed: #{e.message}")
    nil
  end

  # Extract response content from LLM
  def extract_response_content(response)
    case response
    when String
      response
    when Hash
      response["content"] || response[:content] || response.to_s
    else
      if response.respond_to?(:content)
        response.content
      elsif response.respond_to?(:message)
        response.message
      elsif response.respond_to?(:text)
        response.text
      else
        response.to_s
      end
    end
  end

  # Parse the JSON response from LLM
  def parse_intent_response(response_text)
    return nil unless response_text.present?

    # Try to extract JSON from response
    json_match = response_text.match(/\{.*\}/m)
    return nil unless json_match

    begin
      data = JSON.parse(json_match[0])
      {
        intent: data["intent"],
        action: data["action"],
        description: data["description"]
      }
    rescue JSON::ParserError
      nil
    end
  end
end
