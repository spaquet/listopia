# app/services/planning_context_mapper.rb
class PlanningContextMapper
  # Simple mapping of user terms to planning categories
  # This can be easily extended without code changes by moving to database/config
  CONTEXT_MAPPINGS = {
    # Event planning
    "roadshow" => "event planning",
    "conference" => "event planning",
    "convention" => "event planning",
    "meeting" => "event planning",
    "event" => "event planning",
    "workshop" => "event planning",
    "seminar" => "event planning",

    # Travel
    "vacation" => "travel planning",
    "trip" => "travel planning",
    "travel" => "travel planning",
    "holiday" => "travel planning",

    # Personal events
    "wedding" => "wedding planning",
    "party" => "party planning",
    "birthday" => "party planning",

    # Work/Business
    "project" => "project management",
    "launch" => "project management",
    "campaign" => "marketing campaign",
    "marketing" => "marketing campaign",

    # Personal
    "goal" => "goal setting",
    "objective" => "goal setting",
    "resolution" => "goal setting",
    "habit" => "habit formation",

    # Practical
    "shopping" => "shopping planning",
    "move" => "moving planning",
    "relocation" => "moving planning",
    "renovation" => "home improvement"
  }.freeze

  def self.map_context(user_input, title = "")
    # Combine user input and title for better context detection
    text_to_analyze = "#{user_input} #{title}".downcase

    # Find the first matching context
    CONTEXT_MAPPINGS.each do |keyword, context|
      return context if text_to_analyze.include?(keyword)
    end

    # Default to generic project planning
    "project planning"
  end

  def self.available_contexts
    CONTEXT_MAPPINGS.values.uniq.sort
  end

  def self.add_context_mapping(keyword, context)
    # Allow runtime addition of new mappings (could be moved to database)
    CONTEXT_MAPPINGS[keyword.downcase] = context
  end
end
