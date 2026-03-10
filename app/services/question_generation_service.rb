# app/services/question_generation_service.rb
#
# Fast synchronous service for generating clarifying questions
# Uses gpt-4o-mini for speed (~1-2 seconds)
# No background jobs, no async complications

class QuestionGenerationService < ApplicationService
  def initialize(list_title:, category:, planning_domain:)
    @list_title = list_title
    @category = category
    @planning_domain = planning_domain || "general"
  end

  def call
    Rails.logger.info("QuestionGenerationService - Generating questions for: #{@list_title}, domain: #{@planning_domain}")

    start_time = Time.current
    questions = generate_questions
    elapsed_ms = ((Time.current - start_time) * 1000).round(2)

    if questions.present?
      Rails.logger.info("QuestionGenerationService - Generated #{questions.length} questions in #{elapsed_ms}ms")
      success(data: { questions: questions })
    else
      Rails.logger.warn("QuestionGenerationService - Failed to generate questions")
      failure(errors: ["Could not generate clarifying questions"])
    end
  rescue => e
    Rails.logger.error("QuestionGenerationService failed: #{e.message}\n#{e.backtrace.take(5).join("\n")}")
    failure(errors: [e.message])
  end

  private

  def generate_questions
    llm_chat = RubyLLM::Chat.new(provider: :openai, model: "gpt-4o-mini")

    system_prompt = build_system_prompt
    user_message = "Generate clarifying questions for: #{@list_title}"

    llm_chat.add_message(role: "system", content: system_prompt)
    llm_chat.add_message(role: "user", content: user_message)

    Rails.logger.info("QuestionGenerationService - Calling LLM")
    response = llm_chat.complete
    response_text = extract_response_content(response)

    Rails.logger.info("QuestionGenerationService - LLM returned, parsing JSON")

    # Parse the JSON response
    json_match = response_text.match(/\{[\s\S]*\}/m)
    return nil unless json_match

    json_to_parse = json_match[0]

    begin
      data = JSON.parse(json_to_parse)
      questions = data["questions"] || []
      questions.take(3)  # Max 3 questions
    rescue JSON::ParserError => e
      Rails.logger.error("QuestionGenerationService - JSON parse error: #{e.message}")
      nil
    end
  end

  def build_system_prompt
    category_value = @category.present? ? @category.upcase : "PROFESSIONAL"

    <<~PROMPT
      You are a seasoned planning assistant. Generate EXACTLY 3 essential clarifying questions for this #{category_value} planning request.

      Request Category: #{category_value}
      Domain: #{@planning_domain}
      Title: "#{@list_title}"

      Respond with ONLY valid JSON (no other text):

      {
        "questions": [
          {"question": "...", "context": "...", "field": "..."},
          {"question": "...", "context": "...", "field": "..."},
          {"question": "...", "context": "...", "field": "..."}
        ]
      }

      Guidelines:
      - Ask about critical missing information
      - Match the category (professional vs personal)
      - Be specific to the domain
      - Each question should clarify scope, timeline, budget, or resources
    PROMPT
  end

  def extract_response_content(response)
    case response
    when RubyLLM::Message
      # Handle RubyLLM::Message with content object
      if response.content.respond_to?(:text)
        response.content.text
      else
        response.content.to_s
      end
    when String
      response
    else
      response.to_s
    end
  end
end
