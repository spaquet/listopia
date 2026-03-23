# app/schemas/question_schema.rb
# Schema for pre-creation planning questions
# Ensures questions always have: question, context, field

class QuestionSchema < RubyLLM::Schema
  array :questions do
    object do
      string :question, description: "The clarifying question to ask the user"
      string :context, description: "Helpful context or example for the question"
      string :field, description: "The parameter field this question helps extract (e.g., 'locations', 'budget', 'timeline')"
    end
  end
end
