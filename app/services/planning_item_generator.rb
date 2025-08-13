# app/services/planning_item_generator.rb
class PlanningItemGenerator
  def initialize(title, description, context, user = nil)
    @title = title
    @description = description
    @context = context
    @user = user || User.first # Fallback to first user if none provided
  end

  def generate_items
    # Use an LLM to generate contextually appropriate planning items
    prompt = build_planning_prompt

    begin
      response = call_llm_for_planning(prompt)
      parse_planning_response(response)
    rescue => e
      Rails.logger.error "Failed to generate AI planning items: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      []
    end
  end

  private

  def build_planning_prompt
    # Create a dynamic, contextual prompt that considers the specific request
    <<~PROMPT
      You are an expert planning assistant. Generate 6-10 specific, actionable planning items for this request:

      Title: #{@title}
      Description: #{@description}
      Planning Context: #{@context}

      IMPORTANT: Analyze the request carefully and create items that are:
      1. Specific to this exact situation (not generic)
      2. Actionable and clear
      3. Logically ordered by priority/sequence
      4. Relevant to the user's stated goals and preferences

      Pay special attention to any specific details mentioned (like "Air France", "Amex card", dates, locations, preferences).

      Respond with a JSON array where each item has:
      - title: Specific, action-oriented task (incorporate mentioned details where relevant)
      - description: Detailed explanation of what needs to be done and how
      - type: one of "task", "milestone", "reminder", "note"
      - priority: one of "high", "medium", "low" (based on urgency and importance)

      Example for a Paris trip with Air France and Amex:
      [
        {
          "title": "Book Air France flights to Paris for October 25",
          "description": "Search and book round-trip flights using your Amex card for points/benefits. Consider flight times and layovers.",
          "type": "task",
          "priority": "high"
        },
        {
          "title": "Research Paris accommodation near attractions",
          "description": "Find hotels or Airbnb in central Paris, considering proximity to sites you want to visit and transportation.",
          "type": "task",
          "priority": "high"
        }
      ]

      Make items specific to the actual request. Respond only with valid JSON.
    PROMPT
  end

  def call_llm_for_planning(prompt)
    # Create a temporary chat for planning generation
    temp_chat = Chat.new(
      user: @user,
      title: "AI Planning: #{@title.truncate(50)}"
    )

    # Use the existing RubyLLM integration through the chat
    response = temp_chat.ask([
      {
        role: "system",
        content: "You are a helpful planning assistant. Always respond with valid JSON only. Do not include any text outside of the JSON array."
      },
      { role: "user", content: prompt }
    ])

    response.content
  rescue => e
    Rails.logger.error "LLM call failed in PlanningItemGenerator: #{e.message}"
    "[]" # Return empty array as fallback
  end

  def parse_planning_response(response)
    # Clean up the response to extract JSON
    json_text = response.strip

    # Remove markdown code blocks if present
    json_text = json_text.gsub(/```json\n?/, "").gsub(/```\n?/, "")

    # Remove any text before the first [ or after the last ]
    json_start = json_text.index("[")
    json_end = json_text.rindex("]")

    if json_start && json_end && json_end > json_start
      json_text = json_text[json_start..json_end]
    end

    # Parse the JSON
    items = JSON.parse(json_text)

    # Validate and clean the items
    valid_items = items.select { |item| valid_planning_item?(item) }
                      .map { |item| symbolize_and_clean_item(item) }
                      .first(10) # Limit to 10 items max

    Rails.logger.info "Generated #{valid_items.length} valid planning items from AI"
    valid_items
  rescue JSON::ParserError => e
    Rails.logger.error "Failed to parse planning JSON: #{e.message}"
    Rails.logger.error "Response was: #{response.truncate(500)}"
    []
  end

  def valid_planning_item?(item)
    item.is_a?(Hash) &&
      item["title"].present? &&
      item["description"].present? &&
      %w[task milestone reminder note].include?(item["type"]) &&
      %w[high medium low].include?(item["priority"])
  end

  def symbolize_and_clean_item(item)
    {
      title: item["title"].to_s.strip,
      description: item["description"].to_s.strip,
      type: item["type"].to_s,
      priority: item["priority"].to_s,
      # Add any other fields that might be useful
      due_date: parse_due_date(item["due_date"]),
      url: item["url"].present? ? item["url"].to_s : nil,
      metadata: extract_metadata(item)
    }.compact
  end

  def parse_due_date(date_string)
    return nil unless date_string.present?

    # Try to parse various date formats
    Date.parse(date_string.to_s)
  rescue ArgumentError
    nil
  end

  def extract_metadata(item)
    # Extract any additional metadata that might be useful
    metadata = {}

    # Add estimated duration if provided
    metadata[:estimated_duration] = item["duration"] if item["duration"].present?

    # Add category or tags if provided
    metadata[:category] = item["category"] if item["category"].present?
    metadata[:tags] = item["tags"] if item["tags"].present?

    # Add location if provided
    metadata[:location] = item["location"] if item["location"].present?

    metadata.empty? ? nil : metadata
  end
end
