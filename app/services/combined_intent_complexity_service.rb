# app/services/combined_intent_complexity_service.rb
#
# OPTIMIZATION: Single LLM call for intent + complexity + parameters
# Instead of 3 separate calls (saves ~2-3 seconds)
#
# Combines:
# 1. AiIntentRouterService - determine intent
# 2. ListComplexityDetectorService - detect if list is complex
# 3. ParameterExtractionService - extract parameters
#
# All in one efficient LLM call

class CombinedIntentComplexityService < ApplicationService
  def initialize(user_message:, chat:, user:, organization:)
    @user_message = user_message
    @chat = chat
    @user = user
    @organization = organization
  end

  def call
    begin
      response = detect_intent_complexity_and_parameters

      if response.blank?
        return success(data: fallback_response)
      end

      parse_combined_response(response)
    rescue StandardError => e
      Rails.logger.error("Combined intent+complexity+parameter detection failed: #{e.message}")
      success(data: fallback_response)
    end
  end

  private

  def detect_intent_complexity_and_parameters
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
      Analyze the user's message and respond with ONLY a JSON object.

      Return intent classification, complexity assessment, and parameter extraction in a single response.

      {
        "intent": "create_list|create_resource|navigate_to_page|manage_resource|search_data|general_question",
        "action": "action_type",
        "description": "brief description",
        "resource_type": "resource type if applicable or null",

        "is_complex": boolean,
        "complexity_indicators": ["multi_location", "time_bound", "hierarchical", "large_scope", "coordination", "ambiguous", "incomplete"],
        "complexity_confidence": "high|medium|low",
        "complexity_reasoning": "why this is complex or simple",
        "planning_domain": "event|travel|learning|project|business|wellness|general",

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

      INTENT CLASSIFICATION:

      1. "create_list" - Planning/organizing content (books, trips, projects, learning, workouts)
         Examples: "plan my business trip", "reading list for better manager", "vacation to spain", "next sprint planning", "mac update tasks"

      2. "create_resource" - Adding users/teams/organizations
         Examples: "create user john@example.com", "add team Engineering"

      3. "navigate_to_page" - Go to existing page
         Examples: "show users", "list teams"

      4. "search_data" - Find/search information
         Examples: "find lists about budget"

      5. "manage_resource" - Update/delete resources
         Examples: "change user role", "rename team"

      6. "general_question" - Casual conversation
         Examples: "how do I?", "what is?"

      COMPLEXITY ASSESSMENT (ONLY for create_list intent):

      A list is COMPLEX (needs clarifying questions) if:

      ✓ INCOMPLETE - Missing critical info:
        * "vacation to spain" → missing dates, budget, companions, interests
        * "roadshow across US in June" → missing cities, duration, target audience, activities
        * "next sprint planning" → missing team, deliverables, dependencies

      ✓ AMBIGUOUS - Could be interpreted multiple ways:
        * "reading list for better manager" → books/podcasts/courses/coaching?
        * "fitness plan" → gym/home/outdoor/nutrition-focused?

      ✓ DEPENDENT ON CONTEXT - Needs personal constraints:
        * "learning plan for Python" → skill level, goal, timeline, format?
        * "trip to Japan" → when, budget, travel style, companions?

      ✗ SIMPLE - Sufficient information or context-dependent:
        * "grocery list" → user knows what to buy
        * "mac update tasks" → can infer from system context
        * "daily todo" → clear scope
        * "packing list" → straightforward collection

      PARAMETER EXTRACTION:

      For create_list:
      - title: REQUIRED (infer if not explicit)
      - category: professional or personal
      - items: if mentioned

      List missing parameters that need clarification.

      User message: "#{@user_message.content}"
    PROMPT
  end

  def parse_combined_response(response_text)
    json_match = response_text.match(/\{[\s\S]*\}/m)
    return success(data: fallback_response) unless json_match

    begin
      data = JSON.parse(json_match[0])

      # Extract all fields from combined response
      success(data: {
        # Intent fields
        intent: data["intent"] || "general_question",
        action: data["action"] || "chat",
        description: data["description"],
        resource_type: data["resource_type"],

        # Complexity fields (for create_list only)
        is_complex: data["is_complex"] || false,
        complexity_indicators: data["complexity_indicators"] || [],
        complexity_confidence: data["complexity_confidence"] || "medium",
        complexity_reasoning: data["complexity_reasoning"],
        planning_domain: data["planning_domain"] || "general",

        # Parameter fields
        parameters: data["parameters"] || {},
        missing: data["missing"] || [],
        needs_clarification: data["needs_clarification"] || false,
        confidence: data["confidence"] || 0.0
      })
    rescue JSON::ParserError => e
      Rails.logger.warn("Failed to parse combined response: #{e.message}")
      success(data: fallback_response)
    end
  end

  def fallback_response
    {
      intent: "general_question",
      action: "chat",
      description: "Could not determine intent",
      resource_type: nil,
      is_complex: false,
      complexity_indicators: [],
      complexity_confidence: "low",
      complexity_reasoning: "Unable to determine complexity",
      planning_domain: "general",
      parameters: {},
      missing: [],
      needs_clarification: false,
      confidence: 0.0
    }
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
