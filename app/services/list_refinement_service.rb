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
    Rails.logger.warn("ListRefinementService#call - questions returned: #{questions.inspect}, count: #{questions.length}")

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
    Rails.logger.error("List refinement failed: #{e.message}\n#{e.backtrace.join("\n")}")
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
    # Use gpt-5 for reliable question generation
    # This is a critical user-facing feature that needs to work correctly
    # gpt-5-nano with extended thinking was causing parsing issues, so we use the reliable model
    Rails.logger.warn("ListRefinementService#generate_refinement_questions - STARTING")

    llm_chat = RubyLLM::Chat.new(provider: :openai, model: "gpt-5")

    system_prompt = build_refinement_prompt

    # DEBUG: Log the actual prompt being sent
    category_in_prompt = @category.upcase
    domain_in_prompt = @planning_domain || "general"
    Rails.logger.warn("ListRefinementService#generate_refinement_questions - CATEGORY: #{category_in_prompt.inspect}, DOMAIN: #{domain_in_prompt.inspect}")

    llm_chat.add_message(role: "system", content: system_prompt)
    llm_chat.add_message(role: "user", content: "Generate exactly 3 clarifying questions for this list. Match the category (professional vs personal) and domain. Use the provided examples as templates. Be specific and avoid generic questions.")

    Rails.logger.warn("ListRefinementService#generate_refinement_questions - CALLING LLM")
    response = llm_chat.complete
    Rails.logger.warn("ListRefinementService#generate_refinement_questions - LLM RETURNED, extracting content")
    response_text = extract_response_content(response)

    # DEBUG: Log the LLM response
    Rails.logger.warn("ListRefinementService#generate_refinement_questions - RESPONSE LENGTH: #{response_text.length}, PREVIEW: #{response_text[0..500]}")

    # Parse the JSON response
    # Find the outermost JSON object (using greedy match to get the full structure)
    # Extract from first { to last } to get the complete wrapper with "questions" array
    json_match = response_text.match(/\{[\s\S]*\}/m)
    return [] unless json_match

    json_to_parse = json_match[0]
    Rails.logger.warn("ListRefinementService#generate_refinement_questions - EXTRACTED JSON LENGTH: #{json_to_parse.length}, FIRST 300 CHARS: #{json_to_parse[0..300]}")

    begin
      data = JSON.parse(json_to_parse)
      questions = data["questions"] || []

      # Filter to max 3 questions to keep conversation focused
      Rails.logger.warn("ListRefinementService#generate_refinement_questions - PARSED QUESTIONS COUNT: #{questions.length}, QUESTIONS: #{questions.inspect}")
      questions.take(3)
    rescue JSON::ParserError => e
      Rails.logger.error("ListRefinementService#generate_refinement_questions - JSON PARSE ERROR: #{e.message}")
      Rails.logger.error("Attempted to parse: #{json_to_parse[0..500]}")
      []
    end
  rescue => e
    Rails.logger.error("LLM refinement question generation failed: #{e.message}\n#{e.backtrace.take(5).join("\n")}")
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

      ESSENTIAL CLARIFICATION DIMENSIONS:
      Consider these key dimensions when formulating questions:
      - WHO: People involved, roles, team members, stakeholders, audience
      - WHAT: Goals, objectives, deliverables, outcomes, specific items or services
      - WHERE: Locations, venues, regions, physical or digital spaces
      - WHEN: Dates, deadlines, timeline, duration, frequency, schedule
      - WHY: Motivation, business case, purpose, success criteria
      - HOW: Methods, resources, budget, tools, approach, constraints

      ⚠️ CRITICAL CONTEXT - READ THIS FIRST ⚠️

      User's Original Message:
      "#{extract_user_message}"

      User's Planning Request:
      - Category: #{category_value} ← THIS DETERMINES WHICH QUESTIONS TO ASK
      - Domain: #{domain_value}
      - Request: "#{@list_title}"
      #{@items.any? ? "- Initial items mentioned: #{@items.join(", ")}" : ""}

      YOUR TASK: Generate EXACTLY 3 ESSENTIAL clarifying questions that match the category ABOVE.

      ⚠️ IMPORTANT: DO NOT ask about information already provided in the user's message above. ⚠️
      ⚠️ This request is classified as #{category_value.downcase} in the #{domain_value} domain. ⚠️

      ==========================================
      📊 PROFESSIONAL CATEGORY QUESTIONS:
      ==========================================
      Use ONLY if Category = "PROFESSIONAL"
      This is a BUSINESS / PROFESSIONAL planning request.
      Ask about business objectives, professional outcomes, metrics, and ROI.

      For ROADSHOW/EVENT domain:
      Question 1: "What is the primary business objective? (e.g., sales, lead generation, product launch, brand awareness, partnership building)"
      Question 2: "Which cities or regions will be included, and what's the total duration?"
      Question 3: "What activities will occur at each stop? (e.g., demos, presentations, exhibitions, networking)"

      For PROJECT domain:
      Question 1: "What is the primary business goal and success metric?"
      Question 2: "What is the timeline and key milestones?"
      Question 3: "Who are the main stakeholders and team members?"

      For TRAVEL domain (business):
      Question 1: "What is the business purpose and expected outcomes?"
      Question 2: "Which locations and what are the travel dates?"
      Question 3: "How many people and what budget/resources are needed?"

      For GENERAL PROFESSIONAL domain:
      Question 1: "What are the primary business goals and success metrics?"
      Question 2: "What is the timeline and key phases?"
      Question 3: "What resources, budget, or team members are involved?"

      ==========================================
      🎉 PERSONAL CATEGORY QUESTIONS:
      ==========================================
      Use ONLY if Category = "PERSONAL"
      This is a PERSONAL / SOCIAL planning request.
      Ask about celebration type, guests, personal preferences, and lifestyle.

      For EVENT/PARTY domain:
      Question 1: "What type of celebration? (birthday, wedding, anniversary, family gathering, reunion)"
      Question 2: "How many guests? Any special needs (dietary, accessibility, theme preferences)?"
      Question 3: "What's your budget and venue preference?"

      For TRAVEL/VACATION domain:
      Question 1: "What's the purpose and what does success look like for you?"
      Question 2: "Which destinations and for how long?"
      Question 3: "Travel companions and constraints (budget, family needs, accessibility)?"

      For LEARNING domain:
      Question 1: "What's your specific learning goal?"
      Question 2: "What's your current experience level?"
      Question 3: "How much time weekly and when should you complete it?"

      For GENERAL PERSONAL domain:
      Question 1: "What is the primary purpose or goal?"
      Question 2: "What's your scope and timeline?"
      Question 3: "What preferences, constraints, or resources are important?"

      ==========================================
      RESPONSE FORMAT (MANDATORY):
      You MUST respond with ONLY valid JSON, no other text:

      {
        "questions": [
          {
            "question": "First clarifying question specific to the category and domain above",
            "context": "why this matters for planning",
            "field": "parameter_type"
          },
          {
            "question": "Second clarifying question",
            "context": "why this matters",
            "field": "parameter_type"
          },
          {
            "question": "Third clarifying question",
            "context": "why this matters",
            "field": "parameter_type"
          }
        ]
      }

      REMEMBER:
      - Generate EXACTLY 3 questions
      - Match the category (PROFESSIONAL or PERSONAL) shown above
      - Match the domain (#{domain_value})
      - Respond with JSON ONLY - no explanations, no preamble
      - Each question must be actionable and specific
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

  # Extract the original user message from the chat context
  def extract_user_message
    return "Create a #{@list_title} list" unless @context&.respond_to?(:chat) && @context.chat.present?

    # Get the last user message from the chat
    last_user_message = @context.chat.messages
      .where(role: "user")
      .order(created_at: :desc)
      .first

    last_user_message&.content || "Create a #{@list_title} list"
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
