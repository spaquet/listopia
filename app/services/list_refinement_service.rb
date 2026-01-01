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
    llm_chat.add_message(role: "user", content: "Generate refinement questions for this list.")

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
    base_prompt = <<~PROMPT
      You are an intelligent assistant helping refine a list creation request.
      Your role is to ask 1-3 clarifying questions that will make the list more useful and actionable.

      Respond with ONLY a JSON object (no other text) in this exact format:
      {
        "questions": [
          {
            "question": "question text to ask user",
            "context": "why this question is relevant",
            "field": "which parameter this helps refine (e.g., 'duration', 'format', 'budget', 'preferences')"
          }
        ]
      }

      List Details:
      - Title: "#{@list_title}"
      - Category: #{@category}
      - Main Items: #{@items.join(", ")}
      #{@nested_sublists.present? ? "- Sub-lists: #{@nested_sublists.map { |s| s.is_a?(Hash) ? s['title'] : s.to_s }.join(', ')}" : ""}

      Guidelines:
      1. Ask questions that help make the list more specific and actionable
      2. Questions should be conversational and natural
      3. Focus on practical constraints: time, budget, format, preferences, dependencies
      4. Avoid obvious or redundant questions
      5. Ask questions that will improve individual items or the overall list structure
      6. Max 3 questions - keep it focused and conversational
      7. Questions should be answerable in 1-2 sentences
      8. For nested structures (location-based, phase-based):
         - Ask about shared tasks/constraints across sub-lists
         - Ask about sequencing (which phases/locations first)
         - Ask about resource allocation across locations
         - Ask about dependencies between phases

      Category-Specific Guidance:
    PROMPT

    case @category.to_s.downcase
    when "professional"
      base_prompt + <<~PROMPT
        PROFESSIONAL LIST (work/business):
        - Ask about timeline, deadlines, dependencies
        - Ask about team involvement or resources needed
        - Ask about success metrics or acceptance criteria
        - Ask about priorities if there are many items

        Example refinement for "Project Plan":
        - "What's your target completion date for this project?"
        - "Will this require collaboration with other team members?"
        - "Are there any dependencies or blockers to consider?"
      PROMPT
    when "personal"
      base_prompt + <<~PROMPT
        PERSONAL LIST (personal projects, hobbies, self-improvement):
        - Ask about time availability or constraints
        - Ask about format/medium preferences (books, videos, podcasts, audiobooks, etc.)
        - Ask about budget or resource constraints
        - Ask about accessibility or lifestyle considerations

        Example refinement for "Reading List to Be Better Manager":
        - "How much time do you have available for reading each week?"
        - "Are you open to other formats like podcasts or audiobooks for commuting?"
        - "Are there specific management challenges you want to address?"

        Example refinement for "Trip to New York":
        - "How long will you be staying?"
        - "Do you have any dietary restrictions or preferences?"
        - "What's your approximate budget for accommodations?"
      PROMPT
    else
      base_prompt
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
