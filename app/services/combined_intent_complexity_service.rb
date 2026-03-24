# app/services/combined_intent_complexity_service.rb
#
# OPTIMIZATION: Single LLM call for intent + complexity + parameters
# Instead of 3 separate calls (saves ~2-3 seconds)
#
# Combines:
# 1. AiIntentRouterService - determine intent
# 2. Complexity detection - check if list is complex (uses LLM criteria)
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
    # Use gpt-4o-mini for fast classification (no extended thinking needed)
    # This is just intent + complexity detection, not reasoning
    llm_chat = RubyLLM::Chat.new(
      provider: :openai,
      model: "gpt-4.1-nano"
    )

    system_prompt = build_combined_prompt
    llm_chat.add_message(role: "system", content: system_prompt)
    llm_chat.add_message(role: "user", content: "Analyze the user message above.")

    # TIMING: Measure LLM call duration
    start_time = Time.current
    response = llm_chat.complete
    elapsed_ms = ((Time.current - start_time) * 1000).round(2)

    Rails.logger.warn("CombinedIntentComplexityService - LLM call took #{elapsed_ms}ms")

    extract_response_content(response)
  rescue => e
    Rails.logger.error("LLM call failed in combined service: #{e.message}")
    nil
  end

  def build_combined_prompt
    <<~PROMPT
      Analyze this message and return ONLY valid JSON (no markdown, no text before/after).

      {
        "intent": "create_list|create_resource|navigate_to_page|manage_resource|search_data|general_question",
        "is_complex": true/false,
        "complexity_confidence": "high|medium|low",
        "complexity_reasoning": "brief explanation",
        "planning_domain": "event|travel|learning|project|business|general",
        "parameters": {"title": "...", "category": "professional|personal"},
        "generation_type": "items|planning",
        "missing": ["field1", "field2"],
        "confidence": 0.9
      }

      INTENT:
      - create_list: "create/build/plan X", "I want X items/books/recipes", "give me a list of", "organize X", explicit creation requests
      - general_question: "What X should I Y?", "How do I...?", "Tell me about...", advisory/recommendation questions
      - create_resource: adding users/teams/organizations
      - navigate_to_page: show/list pages, "go to", "take me to"
      - search_data: find/search, "find X", "search for"
      - manage_resource: update/delete/archive existing lists

      COMPLEXITY (for create_list only):
      COMPLEX = request is MISSING CRITICAL INFO:
      ✓ "roadshow across US in June" → missing: cities, dates, budget, activities, audience
      ✓ "vacation to spain this summer" → missing: dates, budget, companions, interests
      ✓ "sprint planning" → missing: team size, deliverables, timeline
      ✓ "plan a product launch" → missing: timeline, phases, team, deliverables

      NOT COMPLEX = user intent is clear AND quantity/scope is defined:
      ✗ "grocery list" → user knows what to buy, scope is clear
      ✗ "5 books to become a better manager" → quantity explicit (5), purpose clear (becoming better manager)
      ✗ "3 recipes for weeknight dinners" → quantity (3), purpose (weeknight dinners), scope clear
      ✗ "mac update tasks" → context is sufficient, can infer items
      ✗ "daily todo list" → scope is clear
      ✗ "I need 3 books about marketing" → quantity (3), topic (marketing), scope clear

      MISSING FIELDS RULES:
      Only mark as MISSING if the user did NOT provide it:
      ✗ "I need 5 books" → NOT missing: quantity is "5"
      ✗ "Give me 3 recipes" → NOT missing: quantity is "3"
      ✗ "Plan 4 weekly meetings" → NOT missing: quantity is "4"
      ✓ "Create a list" → MISSING: title/purpose not clear
      ✓ "Plan a roadshow" → MISSING: cities, dates, budget (not explicitly stated)

      GENERATION TYPE (for simple create_list only):
      Detect whether user wants ITEMS or PLANNING STEPS:

      ITEMS = user wants the actual things they requested (not steps to find them):
      ✓ "5 books to become a better manager" → items (user wants 5 book titles)
      ✓ "grocery list for pasta dinner" → items (user wants grocery items)
      ✓ "3 recipes for weeknight dinners" → items (user wants recipe names/ideas)
      ✓ "10 places to visit in Spain" → items (user wants place names)
      ✓ "mac update tasks" → items (system maintenance tasks)

      PLANNING = user wants steps/tasks on how to accomplish something:
      ✓ "plan a roadshow across US cities" → planning (steps: choose cities, book venues, etc.)
      ✓ "organize a product launch" → planning (steps: set timeline, coordinate teams, etc.)
      ✓ "design an onboarding program" → planning (steps: create modules, schedule training, etc.)

      KEY INDICATOR:
      - If user explicitly names what they want (books, recipes, places, tasks) → ITEMS
      - If user names an action/process (plan, organize, design, build, create) → PLANNING

      EXAMPLES:
      - "I'm looking for 5 books to become a better manager" → create_list (explicit: "looking for X")
      - "Give me a grocery list for pasta dinner" → create_list (explicit: "give me a list")
      - "Plan a roadshow across US cities in June" → create_list (explicit: "Plan")
      - "What books should I read on AI?" → general_question (advisory: "What should I read?", not requesting a list)
      - "What type of sailboat should I purchase?" → general_question (advisory: recommendation request)
      - "Create a vacation itinerary to Spain" → create_list (explicit: "Create")
      - "How do I use tags?" → general_question
      - "Create a user john@example.com" → create_resource
      - "Show me the teams page" → navigate_to_page

      User: "#{@user_message.content}"
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

        # Generation type: whether to generate items or planning steps
        generation_type: data["generation_type"] || "planning",

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
      generation_type: "planning",
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
