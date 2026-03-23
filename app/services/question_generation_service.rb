# app/services/question_generation_service.rb
#
# Fast synchronous service for generating clarifying questions
# Uses gpt-4.1-nano for speed (~1-2 seconds)
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
      failure(errors: [ "Could not generate clarifying questions" ])
    end
  rescue => e
    Rails.logger.error("QuestionGenerationService failed: #{e.message}\n#{e.backtrace.take(5).join("\n")}")
    failure(errors: [ e.message ])
  end

  private

  def generate_questions
    system_prompt = build_system_prompt
    user_message = "Generate clarifying questions for: #{@list_title}"

    Rails.logger.info("QuestionGenerationService - Calling LLM with schema")

    # Use RubyLLM::Schema for guaranteed JSON structure
    response = RubyLLM::Chat.new(provider: :openai, model: "gpt-4.1-nano")
      .with_instructions(system_prompt)
      .with_schema(QuestionSchema)
      .ask(user_message)

    Rails.logger.info("QuestionGenerationService - LLM returned structured response")

    # response.content is automatically parsed and validated against schema
    questions = response.content["questions"] || []
    questions.take(3)  # Max 3 questions
  rescue StandardError => e
    Rails.logger.error("QuestionGenerationService - Schema validation or LLM error: #{e.message}")
    nil
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
