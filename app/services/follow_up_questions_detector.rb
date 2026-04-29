# app/services/follow_up_questions_detector.rb
# Detects and extracts follow-up questions from LLM responses
# Converts plain text questions into structured format for clarifying_questions form

class FollowUpQuestionsDetector < ApplicationService
  def initialize(response_text:)
    @response_text = response_text
  end

  def call
    begin
      questions = extract_questions_from_text(@response_text)

      if questions.blank?
        Rails.logger.info("FollowUpQuestionsDetector - No follow-up questions detected")
        return success(data: { questions: [], has_followups: false })
      end

      Rails.logger.info("FollowUpQuestionsDetector - Detected #{questions.length} follow-up questions")
      success(data: { questions: questions, has_followups: true })
    rescue StandardError => e
      Rails.logger.error("FollowUpQuestionsDetector error: #{e.class} - #{e.message}")
      success(data: { questions: [], has_followups: false })
    end
  end

  private

  def extract_questions_from_text(text)
    questions = []

    # Look for patterns like:
    # "Next steps (so I can tailor...)"
    # "Tell me..." / "What's your..."
    # Bullet points with question marks

    # Find "Next steps" or "Next step" or similar section (case-insensitive)
    # Match from "Next steps" or "Next step" until double newline or end of string
    next_steps_match = text.match(/next steps?.*?(?:\n\n|\Z)/im)
    return [] unless next_steps_match

    next_steps_section = next_steps_match[0]

    # Extract bullet point questions
    lines = next_steps_section.split("\n").map(&:strip).reject(&:blank?)

    lines.each do |line|
      # Skip section headers and explanatory text
      next if line.downcase.start_with?("next step")
      next if line.downcase.start_with?("tell me")
      next if line.downcase.start_with?("here")
      next if line.length < 5

      # Look for lines that are questions (end with ?)
      if line.end_with?("?")
        # Remove bullet points and numbering (-, •, *, 1., 2., etc.)
        question_text = line.gsub(/^[-•*\d+\.]\s*/, "").strip

        question_object = {
          question: question_text,
          input_type: determine_input_type(question_text),
          options: extract_options(question_text)
        }

        # Add context if it's parenthetical
        if question_text.include?("(") && question_text.include?(")")
          begin
            context = question_text.match(/\((.*?)\)/)[1]
            question_object[:context] = context
          rescue
            # Ignore if regex fails
          end
        end

        questions << question_object
      end
    end

    questions.take(5)  # Max 5 questions
  end

  def determine_input_type(question_text)
    lowercase_q = question_text.downcase

    # Select input type based on question pattern
    if lowercase_q.include?("or ") || lowercase_q.include?("either") ||
       lowercase_q.include?("new or used") || lowercase_q.include?("inside") ||
       lowercase_q.include?("comfortable")
      "select"
    elsif lowercase_q.include?("describe") || lowercase_q.include?("tell me about") ||
          lowercase_q.include?("explain")
      "textarea"
    else
      "text"
    end
  end

  def extract_options(question_text)
    # Try to extract options from patterns like "new or used" or "inside/outside"
    if question_text.include?(" or ")
      parts = question_text.split(" or ")
      parts.map { |p| p.gsub(/[?()]/, "").strip }.reject(&:blank?)
    elsif question_text.include?("/")
      parts = question_text.split("/")
      parts.map { |p| p.gsub(/[?()]/, "").strip }.reject(&:blank?)
    else
      []
    end
  end
end
