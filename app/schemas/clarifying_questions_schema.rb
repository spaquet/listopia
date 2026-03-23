# app/schemas/clarifying_questions_schema.rb
# Schema for structured clarifying questions in any conversation context
# Used for product recommendations, planning refinement, follow-ups, etc.

class ClarifyingQuestionsSchema < RubyLLM::Schema
  array :questions do
    object do
      string :question,
             description: "The question to ask the user"

      string :context,
             required: false,
             description: "Helpful context or example"

      string :input_type,
             enum: ["text", "textarea", "select"],
             required: false,
             description: "Type of input field (text, textarea, or dropdown selection)"

      array :options,
            of: :string,
            required: false,
            description: "Options if input_type is 'select'"
    end
  end
end
