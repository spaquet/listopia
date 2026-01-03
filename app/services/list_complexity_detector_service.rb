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
    llm_chat = RubyLLM::Chat.new(provider: :openai, model: "gpt-4o-mini")
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
      You are a planning complexity analyzer for a task management system.
      Your job is to determine if a list creation request is COMPLEX (needs upfront planning questions).

      A list request is COMPLEX if it involves any of these indicators:

      1. MULTI-LOCATION: Multiple cities, countries, regions
         Examples: "roadshow across 5 cities", "tour of Europe", "visit NY, LA, and Chicago"

      2. TIME-BOUND PHASES: Structured timeline with stages/phases/milestones
         Examples: "8-week plan", "Q1-Q4 roadmap", "3-month program with phases"

      3. HIERARCHICAL STRUCTURE: Multi-level organization with parent-child relationships
         Examples: "project phases with milestones", "course modules with lessons", "categories with subcategories"

      4. LARGE SCOPE: Comprehensive coverage requiring many coordinated items
         Examples: "complete guide to X", "everything I need for Y", "comprehensive plan"

      5. NESTED COMPLEXITY: Multi-level tasks or dependencies
         Examples: "nested checklists", "dependent tasks", "sequential phases"

      A list is SIMPLE (should return is_complex: false) if it is:
      - Single-location task ("grocery shopping", "daily todo")
      - Flat item list with no structure ("bucket list", "simple checklist")
      - No time phases or hierarchical structure
      - Small scope (<8 items)
      - One-level deep

      RESPOND WITH ONLY THIS JSON (no other text):
      {
        "is_complex": true/false,
        "complexity_indicators": ["multi_location", "time_bound", "hierarchical", "large_scope", "nested"],
        "confidence": "high" | "medium" | "low",
        "reasoning": "1-2 sentence explanation"
      }

      EXAMPLES:

      Input: "Plan my business trip to New York next week"
      Output: {
        "is_complex": false,
        "complexity_indicators": [],
        "confidence": "high",
        "reasoning": "Single-location trip with no time phases or hierarchical structure. Simple planning."
      }

      Input: "Create a roadshow visiting San Francisco, Chicago, Boston, and New York over 4 weeks"
      Output: {
        "is_complex": true,
        "complexity_indicators": ["multi_location", "time_bound"],
        "confidence": "high",
        "reasoning": "Multi-city event with time-bound structure requires location-specific planning."
      }

      Input: "8-week Python learning plan with beginner, intermediate, and advanced modules"
      Output: {
        "is_complex": true,
        "complexity_indicators": ["time_bound", "hierarchical"],
        "confidence": "high",
        "reasoning": "Time-structured program with hierarchical modules requires phase-based organization."
      }

      Input: "Grocery shopping list"
      Output: {
        "is_complex": false,
        "complexity_indicators": [],
        "confidence": "high",
        "reasoning": "Simple flat list with single-level items. No structure or phases needed."
      }

      Input: "I want to become a better marketing manager. Provide me with 5 books to read and a plan to improve in 6 weeks"
      Output: {
        "is_complex": true,
        "complexity_indicators": ["time_bound", "large_scope"],
        "confidence": "high",
        "reasoning": "Professional development with time constraint (6 weeks) and multiple resources benefits from planning."
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

    success(data: {
      is_complex: is_complex,
      complexity_indicators: indicators,
      confidence: confidence,
      reasoning: reasoning
    })
  end

  # Fallback result when detection fails
  def failure_result
    success(data: {
      is_complex: false,
      complexity_indicators: [],
      confidence: "low",
      reasoning: "Unable to determine complexity - defaulting to simple list"
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
