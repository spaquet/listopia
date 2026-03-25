# app/schemas/response_with_questions_schema.rb
# Schema for LLM responses that may include clarifying questions
# Guarantees structured follow-up questions instead of plain text

class ResponseWithQuestionsSchema
  # Define the JSON schema for response with optional follow-up questions
  SCHEMA = {
    type: "object",
    properties: {
      response: {
        type: "string",
        description: "Your conversational response to the user (without questions - those go in the questions array)"
      },
      has_questions: {
        type: "boolean",
        description: "Whether you have follow-up questions to refine your response"
      },
      questions: {
        type: "array",
        description: "Array of follow-up questions if has_questions is true",
        items: {
          type: "object",
          properties: {
            question: {
              type: "string",
              description: "The question text (should end with ?)"
            },
            input_type: {
              type: "string",
              enum: [ "text", "textarea", "select" ],
              description: "How the user should answer: text (single line), textarea (multi-line), or select (dropdown)"
            },
            options: {
              type: "array",
              items: { type: "string" },
              description: "Options for select input type, empty array for text/textarea"
            },
            context: {
              type: "string",
              description: "Optional hint or context to help the user answer"
            }
          },
          required: [ "question", "input_type" ]
        }
      }
    },
    required: [ "response", "has_questions" ]
  }.freeze

  def self.json_schema
    SCHEMA
  end
end
