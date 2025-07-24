# app/services/planning_item_generator.rb
class PlanningItemGenerator
  def initialize(title, description, context)
    @title = title
    @description = description
    @context = context
  end

  def generate_items
    # Use an LLM to generate contextually appropriate planning items
    prompt = build_planning_prompt

    begin
      response = call_llm_for_planning(prompt)
      parse_planning_response(response)
    rescue => e
      Rails.logger.error "Failed to generate AI planning items: #{e.message}"
      []
    end
  end

  private

  def build_planning_prompt
    <<~PROMPT
      You are a planning expert. Generate 6-10 actionable planning items for the following project:

      Title: #{@title}
      Description: #{@description}
      Context: #{@context}

      Create specific, actionable tasks that would help someone successfully plan and execute this project.

      Respond with a JSON array where each item has:
      - title: Brief, action-oriented task name
      - description: Detailed explanation of what needs to be done
      - type: one of "task", "milestone", "reminder", "idea"
      - priority: one of "high", "medium", "low"

      Focus on practical, specific actions rather than generic advice. Consider the unique aspects of this particular project.

      Example format:
      [
        {
          "title": "Research venue options",
          "description": "Find and compare 3-5 potential venues that meet capacity and technical requirements",
          "type": "task",
          "priority": "high"
        }
      ]

      Respond only with valid JSON.
    PROMPT
  end

  def call_llm_for_planning(prompt)
    # Create a temporary chat for planning generation
    user = User.first # You might want to pass the actual user here
    temp_chat = Chat.new(user: user, title: "Planning Generation")

    # Use the existing RubyLLM integration through the chat
    response = temp_chat.ask([
      { role: "system", content: "You are a helpful planning assistant. Always respond with valid JSON only." },
      { role: "user", content: prompt }
    ])

    response.content
  rescue => e
    Rails.logger.error "LLM call failed: #{e.message}"
    "[]" # Return empty array as fallback
  end

  def parse_planning_response(response)
    # Clean up the response to extract JSON
    json_text = response.strip

    # Remove markdown code blocks if present
    json_text = json_text.gsub(/```json\n?/, "").gsub(/```\n?/, "")

    # Parse the JSON
    items = JSON.parse(json_text)

    # Validate and clean the items
    items.select { |item| valid_planning_item?(item) }
         .map { |item| symbolize_and_clean_item(item) }
         .first(10) # Limit to 10 items max
  rescue JSON::ParserError => e
    Rails.logger.error "Failed to parse planning JSON: #{e.message}"
    Rails.logger.error "Response was: #{response}"
    []
  end

  def valid_planning_item?(item)
    item.is_a?(Hash) &&
      item["title"].present? &&
      item["description"].present? &&
      %w[task milestone reminder idea].include?(item["type"]) &&
      %w[high medium low].include?(item["priority"])
  end

  def symbolize_and_clean_item(item)
    {
      title: item["title"].to_s.strip,
      description: item["description"].to_s.strip,
      type: item["type"].to_s.strip,
      priority: item["priority"].to_s.strip
    }
  end
end
