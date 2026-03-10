# app/services/combined_intent_parameter_service.rb
#
# Optimized service combining intent detection and parameter extraction
# into a single LLM call instead of two separate calls
#
# Saves ~1-2 seconds per message by:
# 1. Single LLM call instead of 2
# 2. Returns both intent and parameters together
# 3. Reduces round-trip latency
#
# Phase 1 optimization for AI acceleration plan

class CombinedIntentParameterService < ApplicationService
  def initialize(user_message:, chat:, user:, organization:)
    @user_message = user_message
    @chat = chat
    @user = user
    @organization = organization
  end

  def call
    begin
      # Single LLM call returns both intent and parameters
      response = detect_intent_and_extract_parameters

      if response.blank?
        # Graceful fallback to general question
        return success(data: {
          intent: "general_question",
          action: "chat",
          parameters: {},
          missing: [],
          confidence: 0.0
        })
      end

      # Parse the response
      parse_combined_response(response)
    rescue StandardError => e
      Rails.logger.error("Combined intent+parameter detection failed: #{e.message}")
      # Fallback to general question on any error
      success(data: {
        intent: "general_question",
        action: "chat",
        parameters: {},
        missing: [],
        confidence: 0.0
      })
    end
  end

  private

  def detect_intent_and_extract_parameters
    llm_chat = RubyLLM::Chat.new(
      provider: :openai,
      model: "gpt-5-nano"
    )

    system_prompt = build_combined_prompt
    llm_chat.add_message(role: "system", content: system_prompt)
    llm_chat.add_message(role: "user", content: "Analyze the user message above.")

    response = llm_chat.complete
    extract_response_content(response)
  rescue => e
    Rails.logger.error("LLM call failed in combined service: #{e.message}")
    nil
  end

  def build_combined_prompt
    <<~PROMPT
      Analyze the user's message and respond with ONLY a JSON object (no other text).
      Return both the intent classification AND parameter extraction in a single response.

      {
        "intent": "intent_type",
        "action": "action_type",
        "description": "brief description",
        "resource_type": "resource type if applicable or null",
        "parameters": {
          "title": "if applicable",
          "category": "professional|personal|null",
          "items": [...],
          "name": "if applicable",
          "email": "if applicable"
        },
        "missing": ["field1", "field2"],
        "needs_clarification": false,
        "confidence": 0.95
      }

      AVAILABLE INTENTS AND ACTIONS:

      1. "navigate_to_page" - User wants to go to an existing page
         Examples: "show users", "list teams", "who's in this org"

      2. "create_list" - Planning/organizing/creating content lists
         Examples:
           "plan my business trip"
           "create a grocery list"
           "I want to become a better manager, give me a plan"
           "provide me with 5 books to read"
           "learning plan for Python"
         Category: Professional (business/work) or Personal (personal growth/hobby)

      3. "create_resource" - Adding users/teams/organizations to the app
         Examples:
           "create user john@example.com"
           "add team called Engineering"
           "invite someone to organization"
         Do NOT use for lists, plans, or collections.

      4. "search_data" - Finding/searching information
         Examples: "find lists about budget", "search for users"

      5. "manage_resource" - Updating/deleting existing resources
         Examples: "change user role", "update team name", "suspend user"

      6. "general_question" - General conversation or questions
         Examples: "how do I?", "what is?", casual questions

      CRITICAL DISTINCTION - CREATE_LIST vs CREATE_RESOURCE:

      CREATE_LIST (Content, Plans, Collections, Personal Goals):
      ✓ "Help me improve my public speaking skills"
      ✓ "I want to develop my leadership abilities"
      ✓ "Create a professional development plan"
      ✓ "Plan a trip to Europe"
      ✓ "Build a reading list on leadership"
      ✓ "Create a workout routine for 8 weeks"

      CREATE_RESOURCE (Adding Users/Teams/Orgs to App):
      ✓ "Add user john@company.com"
      ✓ "Create a team called 'Design Team'"
      ✓ "Invite sarah to our organization"

      PARAMETER EXTRACTION RULES:

      For create_list:
      - Extract title (REQUIRED - infer if not explicit)
      - Extract category (professional or personal)
      - Extract items/tasks if mentioned
      - Set needs_clarification: true if category unclear

      For create_resource:
      - resource_type: user, organization, team, list
      - Extract all available parameters
      - List missing required parameters

      User message: "#{@user_message.content}"
    PROMPT
  end

  def parse_combined_response(response_text)
    # Extract JSON from response
    json_match = response_text.match(/\{[\s\S]*\}/m)
    return fallback_response unless json_match

    begin
      data = JSON.parse(json_match[0])

      success(data: {
        intent: data["intent"] || "general_question",
        action: data["action"] || "chat",
        description: data["description"],
        resource_type: data["resource_type"],
        parameters: data["parameters"] || {},
        missing: data["missing"] || [],
        needs_clarification: data["needs_clarification"] || false,
        confidence: data["confidence"] || 0.0
      })
    rescue JSON::ParserError => e
      Rails.logger.warn("Failed to parse combined response: #{e.message}")
      fallback_response
    end
  end

  def fallback_response
    success(data: {
      intent: "general_question",
      action: "chat",
      description: "Could not determine intent",
      resource_type: nil,
      parameters: {},
      missing: [],
      needs_clarification: false,
      confidence: 0.0
    })
  end

  def extract_response_content(response)
    case response
    when String
      response
    when Hash
      response["content"] || response[:content] || response.to_s
    else
      if response.respond_to?(:content)
        content = response.content
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
end
