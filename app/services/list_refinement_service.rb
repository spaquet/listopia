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
    llm_chat = RubyLLM::Chat.new(provider: :openai, model: "gpt-4-turbo")

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
      You are a world-class planning strategist and expert consultant with deep knowledge across multiple domains:
      - Event planning & logistics
      - Travel & hospitality
      - Learning & curriculum design
      - Project management & software development
      - Business strategy & operations
      - Personal productivity & wellness
      - Content creation & publishing
      - Sales & marketing strategy

      Your expertise allows you to ask the RIGHT questions that matter, not generic ones.

      Your task: Ask 2-3 BRILLIANT, SPECIFIC clarifying questions that help someone execute their plan effectively.

      ⚠️ CRITICAL INSTRUCTION:
      - NEVER ask generic questions like "Do you have a budget?" or "What's your timeline?" (too obvious)
      - NEVER ask about team/collaboration in pre-planning (that's a post-creation conversation)
      - ONLY ask questions that are DIRECTLY RELEVANT to their specific planning type
      - EVERY question must be actionable and immediately useful for structuring their plan
      - Questions should be as specific as possible to their domain and context
      - Maximum 2-3 questions (keep it focused, not a survey)

      Respond with ONLY a JSON object (no other text) in this exact format:
      {
        "questions": [
          {
            "question": "specific, thoughtful question phrased naturally",
            "context": "why this matters for their specific goal",
            "field": "parameter type"
          }
        ]
      }

      CONTEXT ABOUT THEIR PLAN:
      - Title: "#{@list_title}"
      - Category: #{@category}
      - Planning Type: #{planning_type}
      - Items they mentioned: #{@items.join(", ")}
      #{@nested_sublists.present? ? "- Sub-lists: #{@nested_sublists.map { |s| s.is_a?(Hash) ? s['title'] : s.to_s }.join(', ')}" : ""}

      CORE PRINCIPLES:
      1. ✅ DOMAIN EXPERTISE: Use your knowledge of their planning domain to ask smart questions
      2. ✅ RELEVANCE: Every question directly impacts how they'll structure their plan
      3. ✅ SPECIFICITY: Show you understand THEIR situation, not generic planning
      4. ✅ ACTIONABILITY: Questions should yield information they'll immediately use
      5. ✅ NATURAL TONE: Sound like a knowledgeable colleague, not a form
      6. ✅ AVOID OBVIOUS: Don't ask questions everyone would think of
      7. ✅ AVOID PREMATURE: Don't ask about collaboration/team at this stage

      ============================================================
      PLANNING TYPE-SPECIFIC GUIDANCE - FOLLOW EXACTLY
      ============================================================
      #{context_specific_guidance}

      ============================================================
      GENERATION:
      Based on the guidance above, generate 2-3 questions that:
      - Match the examples in style and specificity
      - Are directly relevant to their stated planning type
      - Will help them structure their plan better
      - Are actionable and immediately useful
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
        This is a complex, multi-location event requiring strategic coordination.
        Focus on questions that unlock KEY STRUCTURAL DECISIONS they need to make:

        Critical factors for roadshow planning:
        - Geographic scope: Which cities/regions? (This defines your entire structure)
        - Timeline: Duration total? Schedule between stops? (Affects logistics and staffing)
        - Format consistency: Same content/setup at each location or customized? (Impacts planning)
        - Venue/logistics: Pre-booked or scouting needed? (Affects timeline)
        - Operational model: Who travels? Local teams? (Impacts coordination)
        - Target audience: Same demographic at each stop? (Affects messaging/planning)

        EXAMPLE QUESTIONS - Focus on structural decisions:
        - "Which cities or regions will this roadshow visit, and what's your target reach?"
        - "Will the roadshow have the same format and content at each location, or will you customize for each city?"
        - "How much time will you spend at each location, and do you know your stops yet or are you still planning the route?"

        DO NOT ask generic questions about budget, timeline, or team at this stage.
        INSTEAD, ask questions that help them make structural decisions about HOW to organize the roadshow.
      PROMPT
    when :travel
      <<~PROMPT
        SPECIAL GUIDANCE - TRAVEL/VACATION:
        Focus on KEY STRUCTURAL DECISIONS that shape their itinerary:

        Critical factors:
        - Geographic routing: Which destinations and in what order? (Affects logistics)
        - Duration split: How many days at each location? (Affects depth vs breadth)
        - Pace preference: Fast-paced multi-city or slow exploratory? (Affects planning approach)
        - Travel style: Guided/planned or flexible/spontaneous? (Affects structure)
        - Accommodation pattern: Changing daily or hub-based? (Affects logistics)
        - Activities focus: Specific interests/themes? (Affects structure)

        EXAMPLE QUESTIONS - Focus on itinerary structure:
        - "Are you planning to visit multiple countries/cities or focus on one region?"
        - "Do you prefer to stay a few nights in each place and really explore, or visit more places quickly?"
        - "Are there specific activities or experiences you want to prioritize in your trip?"

        DO NOT ask generic questions about budget or group size (not structural).
        INSTEAD, ask what will drive their itinerary planning.
      PROMPT
    when :learning
      <<~PROMPT
        SPECIAL GUIDANCE - LEARNING/SKILL DEVELOPMENT:
        Focus on STRUCTURAL DECISIONS that define their learning path:

        Critical factors:
        - Learning progression: Linear fundamentals-first or modular/flexible? (Affects organization)
        - Content mix: Books, projects, videos, mentoring, certifications? (Affects structure)
        - Real-world application: Building something specific or general mastery? (Affects path)
        - Existing foundation: Beginner, intermediate, or advanced? (Affects path and depth)
        - Cohesion: Standalone courses/books or integrated curriculum? (Affects structure)

        EXAMPLE QUESTIONS - Focus on learning structure:
        - "Are you starting from scratch or building on existing knowledge? This affects how we structure the foundation."
        - "Do you want to learn through hands-on projects, reading and study, video courses, or a mix? This shapes your learning path."
        - "Is there a specific goal you're learning towards (job, side project, mastery)? This helps us tailor the progression."

        DO NOT ask vague questions about time or motivation.
        INSTEAD, ask what learning approach and structure will work for them.
      PROMPT
    when :project
      <<~PROMPT
        SPECIAL GUIDANCE - PROJECT/BUILD:
        Focus on STRUCTURAL DECISIONS that define project execution:

        Critical factors:
        - Project phases: Sequential phases or parallel workstreams? (Affects structure)
        - Deliverables: Single output or incremental releases? (Affects milestone structure)
        - Constraints: Hard deadline vs flexible? Key dependencies or blockers? (Affects critical path)
        - Scope boundaries: MVP vs full vision? Phased rollout? (Affects planning)
        - Quality gates: Testing, review, approval processes? (Affects structure)

        EXAMPLE QUESTIONS - Focus on project structure:
        - "What's your overall vision, and are we building towards an MVP first or the full solution?"
        - "Do the major components need to be built sequentially, or can some work happen in parallel?"
        - "Are there hard deadlines or dependencies that constrain the timeline?"

        DO NOT ask about team or collaboration at this stage.
        INSTEAD, ask what will shape the project's execution structure.
      PROMPT
    when :fitness
      <<~PROMPT
        SPECIAL GUIDANCE - FITNESS/WORKOUT:
        Focus on STRUCTURAL DECISIONS for their fitness program:

        Critical factors:
        - Training approach: Strength, endurance, flexibility, mixed? (Affects structure)
        - Progression model: Progressive overload, periodization, phases? (Affects organization)
        - Recovery/variety: Same routine or rotating workouts? (Affects structure)
        - Environment: Gym, home, outdoor, mixed? (Affects exercise selection)
        - Constraints: Injuries, equipment limitations, time? (Affects planning)

        EXAMPLE QUESTIONS:
        - "What's your primary fitness goal - strength, endurance, flexibility, or overall fitness?"
        - "Do you prefer doing the same routine consistently, or rotating different workouts for variety?"
        - "What equipment or environment do you have access to?"
      PROMPT
    when :routine
      <<~PROMPT
        SPECIAL GUIDANCE - ROUTINE/HABIT:
        Focus on STRUCTURAL DECISIONS for recurring activities:

        Critical factors:
        - Frequency & timing: Daily/weekly rhythm and specific times? (Affects structure)
        - Triggers & context: What initiates the routine? (Affects organization)
        - Variations: Seasonal changes, exceptions, flexibility? (Affects structure)
        - Purpose: Habit-building, maintenance, optimization? (Affects approach)
        - Environment: Home, office, mixed, travel-friendly? (Affects structure)

        EXAMPLE QUESTIONS:
        - "Is this something you'll do daily, weekly, or on a specific schedule?"
        - "Do you want the same routine every time, or should it vary based on season or circumstances?"
        - "What triggers will help you remember to do this routine?"
      PROMPT
    else
      <<~PROMPT
        SPECIAL GUIDANCE - GENERAL LIST:
        Ask context-aware questions about their specific planning needs:
        - What's the primary purpose or outcome they're after?
        - What are the key constraints or dependencies?
        - Is there a specific structure or organization they prefer?
        - What would make this list most useful for them?

        Focus on understanding their situation deeply, not generic planning questions.
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
