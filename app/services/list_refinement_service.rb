# app/services/list_refinement_service.rb
#
# Intelligent refinement agent that asks clarifying questions for list creation
# Acts like a professional assistant by understanding context and asking relevant follow-ups
#
# Examples:
# - "Book hotel" for trip → ask about duration, location preferences, budget
# - "Reading list to be better manager" → ask about time availability, format preferences (books/podcasts/audiobooks)
# - "Grocery shopping" → ask about dietary restrictions, household size, budget
# - "Project plan" → ask about timeline, team size, dependencies

class ListRefinementService < ApplicationService
  def initialize(list_title:, category:, items:, context:, nested_sublists: [], planning_domain: nil)
    @list_title = list_title
    @category = category
    @items = items
    @context = context
    @nested_sublists = nested_sublists
    @planning_domain = planning_domain

    # DEBUG: Log all initialization parameters
    Rails.logger.warn("ListRefinementService#initialize - INIT PARAMS - title: #{@list_title.inspect}, category: #{@category.inspect}, domain: #{@planning_domain.inspect}, items: #{@items.inspect}")
  end

  def call
    # Analyze list and generate intelligent follow-up questions
    questions = generate_refinement_questions

    # Log the context being used for refinement
    Rails.logger.info("ListRefinementService call - title: #{@list_title}, category: #{@category}, domain: #{@planning_domain}, items: #{@items.inspect}")

    if questions.present?
      refinement_ctx = build_refinement_context
      Rails.logger.info("ListRefinementService refinement_context: #{refinement_ctx.inspect}")
      success(data: {
        needs_refinement: true,
        questions: questions,
        refinement_context: refinement_ctx
      })
    else
      success(data: {
        needs_refinement: false,
        questions: [],
        refinement_context: {}
      })
    end
  rescue => e
    Rails.logger.error("List refinement failed: #{e.message}")
    # Graceful fallback - proceed without refinement
    success(data: {
      needs_refinement: false,
      questions: [],
      refinement_context: {}
    })
  end

  private

  # Generate clarifying questions based on list type and items
  def generate_refinement_questions
    # Use gpt-4-turbo for intelligent question generation
    # This requires deeper reasoning about domain-specific planning decisions
    llm_chat = RubyLLM::Chat.new(provider: :openai, model: "gpt-4-turbo")

    system_prompt = build_refinement_prompt

    # DEBUG: Log the actual prompt being sent
    category_in_prompt = @category.upcase
    domain_in_prompt = @planning_domain || "general"
    Rails.logger.warn("ListRefinementService#generate_refinement_questions - PROMPT VARS - category: #{category_in_prompt.inspect}, domain: #{domain_in_prompt.inspect}")
    Rails.logger.debug("ListRefinementService#generate_refinement_questions - PROMPT SNIPPET - #{system_prompt[0..500]}")

    llm_chat.add_message(role: "system", content: system_prompt)
    llm_chat.add_message(role: "user", content: "Generate exactly 3 clarifying questions for this list. Match the category (professional vs personal) and domain. Use the provided examples as templates. Be specific and avoid generic questions.")

    response = llm_chat.complete
    response_text = extract_response_content(response)

    # DEBUG: Log the LLM response
    Rails.logger.warn("ListRefinementService#generate_refinement_questions - LLM RESPONSE - #{response_text[0..800]}")

    # Parse the JSON response
    json_match = response_text.match(/\{[\s\S]*\}/m)
    return [] unless json_match

    begin
      data = JSON.parse(json_match[0])
      questions = data["questions"] || []

      # Filter to max 3 questions to keep conversation focused
      Rails.logger.warn("ListRefinementService#generate_refinement_questions - PARSED QUESTIONS - #{questions.inspect}")
      questions.take(3)
    rescue JSON::ParserError
      []
    end
  rescue => e
    Rails.logger.error("LLM refinement question generation failed: #{e.message}")
    []
  end

  # Build context-specific refinement prompt
  def build_refinement_prompt
    # LLM receives planning_domain (e.g., "event", "travel", "learning")
    # It will use its own knowledge to determine what questions to ask

    # DEBUG: Check what values we're about to use
    category_value = @category.present? ? @category.upcase : "MISSING_CATEGORY"
    domain_value = @planning_domain.present? ? @planning_domain : "general"
    Rails.logger.warn("BUILD_REFINEMENT_PROMPT - @category: #{@category.inspect}, category_value: #{category_value.inspect}, @planning_domain: #{@planning_domain.inspect}, domain_value: #{domain_value.inspect}")

    base_prompt = <<~PROMPT
      You are a seasoned planning assistant with universal expertise. Your task is to understand the planning request deeply and ask clarifying questions to collect ALL essential information needed to structure the work into organized, actionable lists.

      CRITICAL RULE: You are NOT creating the list yet. You are asking questions to UNDERSTAND THE TASK COMPLETELY before structuring it.

      ⚠️ CRITICAL CONTEXT - READ THIS FIRST ⚠️

      User's Planning Request:
      - Category: #{category_value} ← THIS DETERMINES WHICH QUESTIONS TO ASK
      - Domain: #{domain_value}
      - Request: "#{@list_title}"
      #{@items.any? ? "- Initial items mentioned: #{@items.join(", ")}" : ""}

      YOUR TASK: Generate exactly 3 ESSENTIAL clarifying questions that match the category ABOVE.

      ⚠️ DETERMINE THE TYPE FIRST ⚠️

      Step 1: Check the CATEGORY field above.
      - If it says "PROFESSIONAL" → Use PROFESSIONAL questions below
      - If it says "PERSONAL" → Use PERSONAL questions below

      Step 2: Check the DOMAIN field above.
      - This further specifies the type (event, travel, learning, etc.)

      Step 3: Generate 3 questions matching BOTH category AND domain

      ==========================================
      📊 IF CATEGORY = "PROFESSIONAL":
      ==========================================
      This is a BUSINESS / PROFESSIONAL planning request.
      Ask about business objectives, professional outcomes, metrics, and ROI.

      IF DOMAIN = "event" (professional event, ROADSHOW, conference):
      ✓ WHAT: "What is the main business objective of this ROADSHOW? (e.g., sales, lead generation, product launch, brand awareness, partnership building)"
      ✓ WHERE/WHEN: "Which cities or regions will you visit, and how long should the ROADSHOW run in total?"
      ✓ HOW: "What activities or formats will you use at each stop? (e.g., product demos, presentations, workshops, exhibitions, networking events)"

      IF DOMAIN = "project":
      ✓ WHY/WHAT: "What is the primary business goal and success metric for this project?"
      ✓ WHEN: "What is the timeline and key phases/milestones?"
      ✓ WHO: "Who are the stakeholders and team members involved?"

      IF DOMAIN = "travel" (business trip, corporate retreat):
      ✓ "What is the business purpose and expected outcomes?"
      ✓ "Which locations and dates?"
      ✓ "How many people and what resources are needed?"

      🚫 NEVER ask about personal preferences, guests, dietary restrictions, birthdays, or family for PROFESSIONAL category!

      ==========================================
      🎉 IF CATEGORY = "PERSONAL":
      ==========================================
      This is a PERSONAL / SOCIAL planning request.
      Ask about celebration type, guests, personal preferences, and lifestyle.

      IF DOMAIN = "event" (birthday, party, celebration, gathering):
      ✓ "What type of celebration are you planning? (e.g., birthday, wedding, anniversary, family gathering, reunion)"
      ✓ "How many guests are you expecting, and are there any special preferences or constraints (dietary, accessibility, theme)?"
      ✓ "What is your budget and venue preference?"

      IF DOMAIN = "travel" (vacation, holiday, personal trip):
      ✓ "What is the purpose of this trip and what does success look like for you?"
      ✓ "Which destinations are you visiting and for how long?"
      ✓ "Any travel companions and constraints (budget, family needs, accessibility)?"

      IF DOMAIN = "learning" (personal development, hobby):
      ✓ "What is your specific learning goal? (career, hobby, skill development, curiosity)"
      ✓ "What's your current experience level with this topic?"
      ✓ "How much time weekly can you dedicate and when do you want to complete it?"

      🚫 NEVER ask about business objectives, ROI, stakeholders, or professional metrics for PERSONAL category!

      ==========================================
      IF DOMAIN = "general" (unknown or mixed):
      ==========================================
      Ask broad clarifying questions based on the category:
      - Professional: Goals, timeline, resources, success metrics
      - Personal: Purpose, scope, preferences, constraints

      ==========================================
      FINAL REQUIREMENTS:
      1. ✅ CHECK CATEGORY FIRST: Look at "Category:" field above
      2. ✅ MATCH CATEGORY: Professional questions for professional, personal for personal
      3. ✅ MATCH DOMAIN: Use domain-specific examples
      4. ✅ EXACTLY 3 QUESTIONS: No more, no less
      5. ✅ AVOID MISMATCHES: Never mix professional and personal question types
      6. ✅ BE SPECIFIC: Each question should be clear and actionable

      Respond with ONLY a JSON object (no other text):
      {
        "questions": [
          {
            "question": "specific, clear question that gathers essential information",
            "context": "why this matters for planning",
            "field": "parameter type"
          }
        ]
      }
    PROMPT

    base_prompt
  end


  # Build context for storing refinement answers
  def build_refinement_context
    {
      list_title: @list_title,
      category: @category,
      initial_items: @items,
      refinement_stage: "awaiting_answers",
      created_at: Time.current
    }
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
