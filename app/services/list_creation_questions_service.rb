# app/services/list_creation_questions_service.rb
#
# Generates clarifying questions for complex list creation requests
# Uses LLM to identify what details are missing or ambiguous

class ListCreationQuestionsService < ApplicationService
  def initialize(user_message_content:, planning_domain: "general", is_complex: true)
    @user_message = user_message_content
    @planning_domain = planning_domain
    @is_complex = is_complex
  end

  def call
    begin
      return success(data: []) unless @is_complex

      questions = generate_questions_with_llm
      formatted = format_questions(questions)

      success(data: formatted)
    rescue => e
      Rails.logger.error("ListCreationQuestionsService error: #{e.class} - #{e.message}")
      # Graceful fallback: return 1 generic question
      success(data: [
        {
          "question" => "What specific details would help me create a better list for you?",
          "context" => "Any additional context about scope, timeline, or preferences",
          "input_type" => "text"
        }
      ])
    end
  end

  private

  def generate_questions_with_llm
    prompt = build_prompt
    response = RubyLLM::Chat.new(provider: :openai, model: "gpt-4.1-mini")
      .with_instructions(prompt)
      .ask("Generate 2-3 clarifying questions for this list creation request. Return as JSON array.")

    # Parse response - handle both string and Hash responses
    response_text = response.is_a?(String) ? response : response.to_s
    extract_questions_from_response(response_text)
  rescue => e
    Rails.logger.warn("ListCreationQuestionsService LLM call failed: #{e.message}")
    []
  end

  def build_prompt
    <<~PROMPT
      You are helping a user create a list. They said: "#{@user_message}"

      This request appears to be about: #{@planning_domain}

      Generate 2-3 clarifying questions that would help create a better, more specific list.

      Questions should be:
      - Specific and actionable (not vague)
      - About scope, timeline, preferences, or constraints
      - One per question (don't combine)

      Return ONLY a JSON array like:
      [
        {"question": "...", "context": "...", "input_type": "text"},
        {"question": "...", "context": "...", "input_type": "text"}
      ]

      Never include additional text outside the JSON.
    PROMPT
  end

  def extract_questions_from_response(response_text)
    # Try to extract JSON array from response
    json_match = response_text.match(/\[[\s\S]*\]/)
    return [] unless json_match

    parsed = JSON.parse(json_match[0])
    parsed.is_a?(Array) ? parsed : []
  rescue JSON::ParserError
    []
  end

  def format_questions(questions)
    questions.map do |q|
      {
        "question" => q["question"] || q[:question] || "",
        "context" => q["context"] || q[:context] || "",
        "input_type" => q["input_type"] || q[:input_type] || "text"
      }
    end.select { |q| q["question"].present? }
  end
end
