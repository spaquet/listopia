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

      - Intent: "create_list", Action: "chat", Description: User wants to plan/create a list with items
        Examples:
          "plan my business trip"
          "create a grocery list"
          "organize my tasks"
          "plan for next week"
          "give me 5 books to read"
          "i want to become a better manager, create a plan for 6 weeks"
          "provide me with a list of tasks to complete"
          "i want to improve my marketing skills, give me a learning plan"
        This is for planning/organizing, creating learning plans, curating collections, task organization, etc.
        NOT creating user/team/org resources.

      - Intent: "create_resource", Action: "chat", Description: User wants to create user/team/organization
        Examples:
          "create user john@example.com"
          "add team called Engineering"
          "invite someone to our organization"
          "add anna to the team"
          "create new organization for our startup"
        Do NOT use this for creating lists, plans, or collections - use "create_list" instead.

      - Intent: "search_data", Action: "chat", Description: User wants to search/find something
        Examples: "find lists about budget", "search for users", etc.

      - Intent: "manage_resource", Action: "chat", Description: User wants to update/delete EXISTING resources
        Examples: "update user role", "suspend user", "change team name", "promote anna to admin", etc.

      - Intent: "general_question", Action: "chat", Description: General question/conversation
        Examples: "how do I?", "what is?", "tell me about", casual questions, etc.

      CRITICAL DISTINCTION - CREATE_LIST vs CREATE_RESOURCE:

      CREATE_LIST (Planning, Learning, Collections, Personal Goals, Development):
      ✓ "I want to become a better marketing manager"
      ✓ "I'm forward to becoming a better Marketing Manager"
      ✓ "Help me improve my public speaking skills"
      ✓ "I want to develop my leadership abilities"
      ✓ "Create a professional development plan for me"
      ✓ "Provide me with 5 books to read and a plan to improve in 6 weeks"
      ✓ "Give me a learning plan for Python"
      ✓ "Create a workout routine for 8 weeks"
      ✓ "Plan a trip to Europe"
      ✓ "Build a reading list on leadership"
      ✓ "What courses should I take to learn AI?"
      ✓ "Help me organize my business trip itinerary"
      ✓ "Plan our roadshow across 5 US cities"
      ✓ "I want to grow my network - give me a strategy"
      ✓ "Help me become more effective as a manager"
      ✓ "Create a onboarding checklist for new team members"

      CREATE_RESOURCE (Adding Users, Teams, Organizations to the App):
      ✓ "Add user john@company.com"
      ✓ "Create user Josh with email josh@company.com"
      ✓ "Create a team called 'Design Team'"
      ✓ "Invite sarah to our organization"
      ✓ "Add a new team member"
      ✓ "Create organization for XYZ company"
      ✓ "Register 5 new users for the system"

      KEY RULE: If the user mentions self-improvement, skill development, learning, or personal/professional growth → CREATE_LIST
      KEY RULE: If the user is asking to add people/teams/orgs TO THIS APPLICATION with specific names/emails → CREATE_RESOURCE
      KEY RULE: Look at the CONTENT of the request:
        - Does it ask for a plan, guide, structure, items, or content? → CREATE_LIST
        - Does it ask to add someone to the app or create an account? → CREATE_RESOURCE

      Classify based on the user's clear intent, regardless of language or phrasing.
      When in doubt, lean towards CREATE_LIST for personal/professional development requests.

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
      # Handle RubyLLM::Message with RubyLLM::Content
      if response.respond_to?(:content)
        content = response.content
        # If content is a RubyLLM::Content object with text attribute
        if content.respond_to?(:text)
          content.text
        else
          content
        end
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
