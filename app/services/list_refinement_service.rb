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
  def initialize(list_title:, category:, items:, context:, nested_sublists: [])
    @list_title = list_title
    @category = category
    @items = items
    @context = context
    @nested_sublists = nested_sublists
  end

  def call
    # Analyze list and generate intelligent follow-up questions
    questions = generate_refinement_questions

    if questions.present?
      success(data: {
        needs_refinement: true,
        questions: questions,
        refinement_context: build_refinement_context
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
    llm_chat = RubyLLM::Chat.new(provider: :openai, model: "gpt-4o-mini")

    system_prompt = build_refinement_prompt

    llm_chat.add_message(role: "system", content: system_prompt)
    llm_chat.add_message(role: "user", content: "Generate 2-3 refinement questions for this list. Use the provided examples as a template. Generate questions that are SPECIFIC to the planning type detected, not generic project management questions.")

    response = llm_chat.complete
    response_text = extract_response_content(response)

    # Parse the JSON response
    json_match = response_text.match(/\{[\s\S]*\}/m)
    return [] unless json_match

    begin
      data = JSON.parse(json_match[0])
      questions = data["questions"] || []

      # Filter to max 3 questions to keep conversation focused
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
    # Detect the type of planning from the title
    planning_type = detect_planning_type
    context_specific_guidance = build_context_specific_guidance(planning_type)

    base_prompt = <<~PROMPT
      You are an intelligent, thoughtful assistant helping someone organize and plan their activities.
      Your role is to ask 2-3 smart, specific clarifying questions that directly help them execute this plan better.
      Think like a professional organizer or project manager who understands their specific goal.

      ⚠️ CRITICAL INSTRUCTION: You MUST follow the specific guidance below for this planning type.
      Do NOT ask generic project management questions. Do NOT ask about "goals", "budget", "timeline" generically.
      Instead, ask SPECIFIC questions tailored to the planning type detected.

      Respond with ONLY a JSON object (no other text) in this exact format:
      {
        "questions": [
          {
            "question": "specific, thoughtful question",
            "context": "why this matters for their specific goal",
            "field": "parameter type"
          }
        ]
      }

      List Details:
      - Title: "#{@list_title}"
      - Category: #{@category}
      - Planning Type Detected: #{planning_type}
      - Main Items: #{@items.join(", ")}
      #{@nested_sublists.present? ? "- Sub-lists: #{@nested_sublists.map { |s| s.is_a?(Hash) ? s['title'] : s.to_s }.join(', ')}" : ""}

      Core Principles:
      1. BE SPECIFIC: Ask questions that show you understand their EXACT type of planning
      2. BE THOUGHTFUL: Think about what they ACTUALLY need to know to execute this well
      3. AVOID GENERIC: Don't ask obvious questions like "Do you have a budget?" - everyone does
      4. FOCUS ON EXECUTION: Ask what will make them actually DO this successfully
      5. MAX 2-3 QUESTIONS: Keep it focused, not a survey
      6. DIRECT AND ACTIONABLE: Questions should lead to specific, useful information
      7. NATURAL LANGUAGE: Sound like a helpful colleague, not a form
      8. **FOLLOW THE EXAMPLES BELOW**: Use the example questions as templates. Your questions should be similar in specificity and focus.

      ============================================================
      PLANNING TYPE-SPECIFIC GUIDANCE (FOLLOW THIS EXACTLY)
      ============================================================
      #{context_specific_guidance}

      ============================================================
      GENERATION INSTRUCTION:
      Use the example questions above as your template. Generate 2-3 new questions
      that follow the same pattern and specificity as the examples.
      Do not deviate from the planning type guidance provided above.
      ============================================================
    PROMPT

    base_prompt
  end

  # Detect the type of planning from the list title
  def detect_planning_type
    title_lower = @list_title.downcase

    case title_lower
    when /roadshow|tour|event.*traveling|traveling.*event/
      :event_touring
    when /trip|vacation|travel|journey/
      :travel
    when /learning|course|skill|study|training|develop/
      :learning
    when /project|development|build|create|launch/
      :project
    when /workout|fitness|exercise|training/
      :fitness
    when /meal|recipe|cook|food/
      :cooking
    when /reading|book|literature/
      :reading
    when /shopping|purchase|buy/
      :shopping
    when /weekly|monthly|yearly|routine|schedule/
      :routine
    else
      :general
    end
  end

  # Build specific guidance based on the type of planning detected
  def build_context_specific_guidance(planning_type)
    case planning_type
    when :event_touring
      <<~PROMPT
        SPECIAL GUIDANCE - ROADSHOW/TOURING EVENT:
        This is a multi-location event. Focus on questions that will help them organize across locations:
        - Which locations/cities are they visiting? (How many? In what regions?)
        - How many days/weeks? What's the timeline?
        - How many people attending at each location? Expected audience size?
        - Is there a team traveling with them or local partnerships?
        - What's the main purpose at each location? (Same format everywhere or customized?)

        EXAMPLE QUESTIONS FOR ROADSHOW:
        - "Which cities or regions will this roadshow visit?"
        - "How many stops do you plan, and what's the timeline between each location?"
        - "Are you expecting the same audience size at each location, and do you need to customize for each city?"
      PROMPT
    when :travel
      <<~PROMPT
        SPECIAL GUIDANCE - TRAVEL/VACATION:
        Focus on practical constraints that affect the itinerary:
        - Duration and timeline
        - Travel dates and seasonal considerations
        - Budget constraints
        - Traveling solo, with family, with group?
        - Accommodation preferences

        EXAMPLE QUESTIONS FOR TRIPS:
        - "How many days total, and which cities/regions are you visiting?"
        - "Are you traveling solo or with others? Will that affect your itinerary?"
        - "What's your approximate budget range? Does it include flights and accommodation?"
      PROMPT
    when :learning
      <<~PROMPT
        SPECIAL GUIDANCE - LEARNING/SKILL DEVELOPMENT:
        Focus on learning style, timeframe, and existing knowledge:
        - How much time can they dedicate per week?
        - What's their current skill level?
        - Do they prefer hands-on practice, reading, video, interactive?
        - What's the goal timeline?
        - Are there specific real-world applications they want?

        EXAMPLE QUESTIONS FOR LEARNING PLANS:
        - "How many hours per week can you realistically dedicate to this?"
        - "Do you prefer learning through practice projects, videos, books, or a mix?"
        - "What's the timeline - are you learning for a specific deadline or just self-improvement?"
      PROMPT
    when :project
      <<~PROMPT
        SPECIAL GUIDANCE - PROJECT/BUILD:
        Focus on scope, team, timeline, and dependencies:
        - What's the end goal/deliverable?
        - Timeline and deadline?
        - Team size and roles?
        - Budget constraints?
        - Dependencies or blockers?

        EXAMPLE QUESTIONS FOR PROJECTS:
        - "What's your target completion date, and do you have any hard deadlines for milestones?"
        - "Will this require collaboration with others, or are you working solo?"
        - "Are there any external dependencies or resources you need to coordinate?"
      PROMPT
    when :fitness
      <<~PROMPT
        SPECIAL GUIDANCE - FITNESS/WORKOUT:
        Focus on current fitness level, goals, and constraints:
        - Current fitness level and any limitations?
        - Specific fitness goals (strength, endurance, flexibility)?
        - Time available and frequency?
        - Access to equipment or facilities?

        EXAMPLE QUESTIONS FOR FITNESS:
        - "What's your current fitness level, and do you have any injuries or limitations?"
        - "How many days per week can you realistically commit?"
        - "Do you have access to a gym, or will this be home/outdoor workouts?"
      PROMPT
    when :routine
      <<~PROMPT
        SPECIAL GUIDANCE - ROUTINE/HABIT:
        Focus on frequency, triggers, and maintenance:
        - How often (daily, weekly, monthly)?
        - What triggers this routine (time of day, event, season)?
        - How long to maintain?
        - Any variations for different seasons or situations?

        EXAMPLE QUESTIONS FOR ROUTINES:
        - "How often will you follow this routine (daily, weekly, seasonally)?"
        - "What time of day works best, or does it vary?"
        - "Are there variations for different seasons or situations?"
      PROMPT
    else
      <<~PROMPT
        SPECIAL GUIDANCE - GENERAL LIST:
        Ask context-aware questions that help them be successful:
        - What's the main constraint (time, budget, resources)?
        - When do they need this done?
        - Are others involved?
        - What success looks like for them?
      PROMPT
    end
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
