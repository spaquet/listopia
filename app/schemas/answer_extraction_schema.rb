# app/schemas/answer_extraction_schema.rb
# Schema for extracting structured parameters from user's free-form answers
# Ensures consistent extraction of locations, budget, timeline, team, etc.

class AnswerExtractionSchema < RubyLLM::Schema
  array :locations,
        of: :string,
        description: "Cities, regions, or locations mentioned"

  string :budget,
         required: false,
         description: "Total budget if mentioned (e.g., '$50k', 'under $10k')"

  string :timeline,
         required: false,
         description: "Duration or dates (e.g., 'June-September', '3 weeks', 'spring')"

  array :team_members,
        of: :string,
        required: false,
        description: "Names or roles of team members involved"

  string :duration,
         required: false,
         description: "Length of event/project/activity"

  array :activities,
        of: :string,
        required: false,
        description: "Activities, tasks, or services mentioned"

  string :audience,
         required: false,
         description: "Target audience or participants"

  string :category,
         enum: [ "professional", "personal" ],
         required: false,
         description: "Whether this is professional or personal"
end
