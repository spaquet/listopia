# app/services/list_complexity_detector_service.rb
#
# Intelligently detects if a list creation request is complex and requires pre-creation planning.
# Uses LLM-based classification instead of brittle keyword matching.
#
# Examples:
# - "I need to organize a roadshow starting in June" → is_complex: true (multi_location)
# - "8-week Python learning plan with modules" → is_complex: true (time_bound, hierarchical)
# - "Grocery shopping list" → is_complex: false (simple flat list)

class ListComplexityDetectorService < ApplicationService
  def initialize(user_message:, context:)
    @user_message = user_message
    @context = context
  end

  def call
    detect_complexity_with_llm
  end

  private

  # Detect complexity using LLM classification
  def detect_complexity_with_llm
    # Use gpt-5-nano for simple classification task
    llm_chat = RubyLLM::Chat.new(provider: :openai, model: "gpt-5-nano")
    llm_chat.temperature = 0.3 if llm_chat.respond_to?(:temperature=)

    system_prompt = build_complexity_prompt
    llm_chat.add_message(role: "system", content: system_prompt)
    llm_chat.add_message(role: "user", content: "Analyze this list creation request for complexity.")

    response = llm_chat.complete
    response_text = extract_response_content(response)

    # Parse JSON response
    json_match = response_text.match(/\{[\s\S]*\}/m)
    return failure_result unless json_match

    begin
      data = JSON.parse(json_match[0])
      validate_and_return_result(data)
    rescue JSON::ParserError => e
      Rails.logger.error("ListComplexityDetectorService: JSON parse error: #{e.message}")
      failure_result
    end
  rescue StandardError => e
    Rails.logger.error("ListComplexityDetectorService: Detection failed: #{e.message}")
    failure_result
  end

  # Build the system prompt for LLM classification
  def build_complexity_prompt
    <<~PROMPT
      You are a world-class planning and task management expert. Your expertise spans:
      - Project management and strategy
      - Travel and event planning
      - Learning and skill development
      - Business and marketing planning
      - Personal productivity and wellness
      - Product and software development
      - Content creation and publishing
      - And any other domain requiring structured planning

      Your job is to determine if a list creation request is COMPLEX (needs upfront planning questions).

      A list request is COMPLEX if it involves any of these indicators:

      1. MULTI-LOCATION: Multiple cities, countries, regions, venues
         - Requires location-specific coordination
         - Examples: "roadshow across 5 cities", "tour of Europe", "multi-office implementation"

      2. TIME-BOUND WITH PHASES: Structured timeline with distinct stages/phases/milestones
         - Requires sequential or milestone-based organization
         - Examples: "8-week bootcamp", "Q1-Q4 roadmap", "3-month product launch", "semester-based curriculum"

      3. HIERARCHICAL STRUCTURE: Multi-level organization with parent-child relationships
         - Requires nested/categorical organization
         - Examples: "course with modules and lessons", "project with phases and milestones", "product categories with features"

      4. LARGE SCOPE: Comprehensive, multi-faceted planning requiring many coordinated items
         - Requires extensive research and planning
         - Examples: "complete guide to X", "everything needed for Y", "comprehensive [domain] plan"

      5. COORDINATION COMPLEXITY: Involves multiple people, teams, or external dependencies
         - Requires coordination and alignment
         - Examples: "cross-team initiative", "multi-stakeholder project", "collaborative event"

      A list is SIMPLE (should return is_complex: false) if it is:
      - Single-location, single-person task ("grocery shopping", "daily todo", "packing list")
      - Flat, non-hierarchical list ("bucket list", "simple checklist", "to-read list")
      - No time phases or multi-stage structure
      - Limited scope (typically <8 items, or simple items)
      - Single level of organization

      RESPOND WITH ONLY THIS JSON (no other text):
      {
        "is_complex": true/false,
        "complexity_indicators": ["multi_location", "time_bound", "hierarchical", "large_scope", "coordination"],
        "confidence": "high" | "medium" | "low",
        "reasoning": "1-2 sentence explanation of what makes this complex or simple",
        "planning_domain": "travel", "learning", "project", "business", "event", "wellness", "general", etc.
      }

      EXAMPLES:

      Input: "Plan my business trip to New York next week"
      Output: {
        "is_complex": false,
        "complexity_indicators": [],
        "confidence": "high",
        "reasoning": "Single-location trip with simple packing/logistics. Minimal planning complexity.",
        "planning_domain": "travel"
      }

      Input: "I need to organize a roadshow starting in June this year"
      Output: {
        "is_complex": true,
        "complexity_indicators": ["multi_location", "time_bound"],
        "confidence": "high",
        "reasoning": "Roadshow inherently involves multiple locations and time-bound coordination. Requires location-specific and timeline planning.",
        "planning_domain": "event"
      }

      Input: "Create a roadshow visiting San Francisco, Chicago, Boston, and New York over 4 weeks"
      Output: {
        "is_complex": true,
        "complexity_indicators": ["multi_location", "time_bound"],
        "confidence": "high",
        "reasoning": "Multi-city event with explicit timeline requires location-specific planning and schedule coordination.",
        "planning_domain": "event"
      }

      Input: "8-week Python learning plan with beginner, intermediate, and advanced modules"
      Output: {
        "is_complex": true,
        "complexity_indicators": ["time_bound", "hierarchical"],
        "confidence": "high",
        "reasoning": "Time-structured program with hierarchical modules requires phase-based organization and progression tracking.",
        "planning_domain": "learning"
      }

      Input: "Grocery shopping list"
      Output: {
        "is_complex": false,
        "complexity_indicators": [],
        "confidence": "high",
        "reasoning": "Simple flat list of items with no structure, timeline, or coordination needs.",
        "planning_domain": "general"
      }

      Input: "I want to become a better marketing manager. Provide me with 5 books to read and a plan to improve in 6 weeks"
      Output: {
        "is_complex": true,
        "complexity_indicators": ["time_bound", "large_scope"],
        "confidence": "high",
        "reasoning": "Professional development with time constraint (6 weeks) and multiple resources (books, plan) requires structured learning organization.",
        "planning_domain": "learning"
      }

      Input: "Plan a European vacation visiting Paris, Rome, and Barcelona for 3 weeks in July"
      Output: {
        "is_complex": true,
        "complexity_indicators": ["multi_location", "time_bound"],
        "confidence": "high",
        "reasoning": "Multi-country travel with specific timeline requires itinerary coordination, accommodation, and location-specific activities.",
        "planning_domain": "travel"
      }

      Input: "Build a mobile app MVP with design, backend, and frontend phases"
      Output: {
        "is_complex": true,
        "complexity_indicators": ["time_bound", "hierarchical"],
        "confidence": "high",
        "reasoning": "Software project with distinct phases (design, backend, frontend) requires milestone tracking and sequential execution.",
        "planning_domain": "project"
      }

      USER MESSAGE: "#{@user_message.content}"
    PROMPT
  end

  # Validate the LLM response structure
  def validate_and_return_result(data)
    is_complex = data["is_complex"] == true
    indicators = Array(data["complexity_indicators"] || [])
    confidence = data["confidence"] || "medium"
    reasoning = data["reasoning"] || ""
    planning_domain = data["planning_domain"] || "general"

    success(data: {
      is_complex: is_complex,
      complexity_indicators: indicators,
      confidence: confidence,
      reasoning: reasoning,
      planning_domain: planning_domain
    })
  end

  # Fallback result when detection fails
  def failure_result
    success(data: {
      is_complex: false,
      complexity_indicators: [],
      confidence: "low",
      reasoning: "Unable to determine complexity - defaulting to simple list",
      planning_domain: "general"
    })
  end

  # Extract response content from LLM (handles various response formats)
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
