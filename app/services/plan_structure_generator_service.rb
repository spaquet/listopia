# app/services/plan_structure_generator_service.rb
#
# Generates intelligent, hierarchical plan structures using LLM
# Transforms a simple user request into a detailed nested list structure
#
# Input: User goal, duration, budget, preferences
# Output: Nested structure with:
#   - Parent list (main goal)
#   - Sub-lists (phases, months, categories, topics)
#   - Items (specific tasks, resources, activities)
#
# Example: "I need 6 books and a 4-month plan to become a better social marketer"
# Output:
#   Social Marketing Development Plan (parent)
#   ├── Month 1: Foundations (sublist)
#   │   ├── Learn social media basics
#   │   ├── Study audience psychology
#   │   └── Read "Book 1"
#   ├── Month 2: Strategy & Analytics (sublist)
#   │   └── ...
#   └── Recommended Books (sublist)
#       ├── Book 1: Title
#       └── ...

class PlanStructureGeneratorService < ApplicationService
  def initialize(title:, user_context:, duration: nil, budget: nil, preferences: {})
    @title = title
    @user_context = user_context  # User's goal, background, needs
    @duration = duration           # e.g., "4 months", "12 weeks"
    @budget = budget               # e.g., "$500", "unlimited"
    @preferences = preferences     # e.g., {books: 6, languages: ["English"], style: "practical"}
  end

  def call
    Rails.logger.info("PlanStructureGeneratorService#call - Generating plan structure")
    Rails.logger.info("PlanStructureGeneratorService#call - Title: #{@title}, Duration: #{@duration}, Budget: #{@budget}")
    Rails.logger.info("PlanStructureGeneratorService#call - User context: #{@user_context}")

    begin
      # Build the prompt for the LLM to generate structure
      prompt = build_generation_prompt

      # Call the LLM to generate structure
      structure = call_llm_for_structure(prompt)

      unless structure.present?
        Rails.logger.error("PlanStructureGeneratorService#call - LLM returned empty structure")
        return failure(errors: [ "Failed to generate plan structure" ])
      end

      Rails.logger.info("PlanStructureGeneratorService#call - Generated structure: #{structure.inspect}")

      success(data: {
        title: @title,
        structure: structure  # nested_lists format for ListCreationService
      })
    rescue => e
      Rails.logger.error("PlanStructureGeneratorService#call - Error generating plan: #{e.message}")
      failure(errors: [ e.message ])
    end
  end

  private

  # Build the prompt for LLM to generate detailed plan structure
  def build_generation_prompt
    context_parts = []
    context_parts << "Goal: #{@user_context}" if @user_context.present?
    context_parts << "Duration: #{@duration}" if @duration.present?
    context_parts << "Budget: #{@budget}" if @budget.present?

    preferences_str = ""
    if @preferences.present?
      prefs = @preferences.map { |k, v| "#{k}: #{v}" }.join(", ")
      preferences_str = "\nPreferences: #{prefs}"
    end

    context = context_parts.join("\n")

    <<~PROMPT
      Generate a detailed, structured plan for: "#{@title}"

      Context:
      #{context}#{preferences_str}

      You MUST respond with a valid JSON structure that will be used to create nested lists.
      The structure should be hierarchical with multiple levels:
      - Main goal as the parent list
      - Phases, months, categories, or topics as sub-lists
      - Specific tasks, resources, or activities as items within each sub-list

      Return ONLY valid JSON in this exact format (no other text):
      {
        "nested_lists": [
          {
            "title": "Phase/Month/Category Title",
            "description": "Brief description of this phase",
            "items": [
              {
                "title": "Specific task or resource",
                "description": "Details about this task"
              },
              ...
            ]
          },
          ...
        ]
      }

      Guidelines:
      1. Create 3-5 main phases/months/categories as sub-lists
      2. Each sub-list should have 4-7 items
      3. Items should be actionable and specific
      4. Structure should naturally flow (chronological, topical, or logical progression)
      5. Include diverse elements (reading, practice, projects, reflection)
      6. Match the duration/budget constraints
      7. Make items concrete and measurable

      Generate the JSON now:
    PROMPT
  end

  # Call the LLM to generate structure
  def call_llm_for_structure(prompt)
    Rails.logger.info("PlanStructureGeneratorService#call_llm_for_structure - Calling LLM")

    # Use RubyLLM to call Claude
    begin
      # Initialize RubyLLM client
      client = Anthropic::Client.new(api_key: ENV["ANTHROPIC_API_KEY"])

      response = client.messages(
        model: "claude-opus-4-5-20251101",
        max_tokens: 4000,
        messages: [
          {
            role: "user",
            content: prompt
          }
        ]
      )

      # Extract the response content
      content = response.dig("content", 0, "text")

      unless content.present?
        Rails.logger.error("PlanStructureGeneratorService - Empty LLM response")
        return nil
      end

      Rails.logger.info("PlanStructureGeneratorService - LLM response: #{content[0..500]}")

      # Parse the JSON response
      # Try to extract JSON from the response (in case LLM wraps it in markdown)
      json_str = extract_json_from_response(content)

      parsed = JSON.parse(json_str)
      parsed["nested_lists"] || []
    rescue => e
      Rails.logger.error("PlanStructureGeneratorService#call_llm_for_structure - Error: #{e.message}")
      Rails.logger.error(e.backtrace.join("\n"))
      nil
    end
  end

  # Extract JSON from response (handles markdown code blocks)
  def extract_json_from_response(response_text)
    # Try to find JSON block in markdown
    if response_text.include?("```json")
      match = response_text.match(/```json\s*(.*?)\s*```/m)
      return match[1] if match
    end

    # Try to find plain JSON block
    if response_text.include?("```")
      match = response_text.match(/```\s*(.*?)\s*```/m)
      return match[1] if match
    end

    # Return as-is if it looks like JSON
    response_text.strip
  end
end
