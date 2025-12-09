# app/services/list_refinement_processor_service.rb
#
# Processes user answers to refinement questions and enhances the list
# Extracts parameters from answers and updates list items with derived details

class ListRefinementProcessorService < ApplicationService
  def initialize(list:, user_answers:, refinement_context:, context:)
    @list = list
    @user_answers = user_answers
    @refinement_context = refinement_context
    @context = context
  end

  def call
    # Extract parameters from user answers
    extracted_params = extract_refinement_parameters

    # Enhance list items with derived details
    enhancement_result = enhance_list_items(extracted_params)

    if enhancement_result.success?
      success(data: {
        list: @list,
        extracted_params: extracted_params,
        enhancements: enhancement_result.data[:enhancements],
        message: build_refinement_summary(extracted_params, enhancement_result.data[:enhancements])
      })
    else
      failure(errors: enhancement_result.errors)
    end
  rescue => e
    Rails.logger.error("List refinement processing failed: #{e.message}")
    failure(errors: [ e.message ])
  end

  private

  # Extract parameters from user's refinement answers
  def extract_refinement_parameters
    llm_chat = RubyLLM::Chat.new(provider: :openai, model: "gpt-4o-mini")

    system_prompt = <<~PROMPT
      Extract parameters from the user's answers to refinement questions.
      The user has answered questions to refine their list creation.

      List Context:
      - Title: "#{@refinement_context[:list_title]}"
      - Category: #{@refinement_context[:category]}
      - Items: #{@refinement_context[:initial_items].join(", ")}

      Respond with ONLY a JSON object (no other text):
      {
        "extracted_params": {
          "duration": "extracted value if time/duration mentioned",
          "budget": "extracted value if budget mentioned",
          "format": "extracted value if format/medium mentioned",
          "timeline": "extracted value if timeline/deadline mentioned",
          "team_size": "extracted value if team involvement mentioned",
          "preferences": "extracted value if preferences/constraints mentioned",
          "other_details": "any other relevant details mentioned"
        },
        "item_enhancements": {
          "item_name": "suggested enhancement or detail to add"
        }
      }

      Rules:
      1. Extract only information actually mentioned by the user
      2. For item_enhancements, suggest specific details to add to each item based on refinement answers
      3. Be specific and actionable
      4. Include units where applicable (e.g., "3 days", "$2000", "2-3 hours/week")

      User's answers to refinement questions: "#{@user_answers}"
    PROMPT

    llm_chat.add_message(role: "system", content: system_prompt)
    llm_chat.add_message(role: "user", content: "Extract refinement parameters from these answers.")

    response = llm_chat.complete
    response_text = extract_response_content(response)

    # Parse the JSON response
    json_match = response_text.match(/\{[\s\S]*\}/m)
    return {} unless json_match

    begin
      data = JSON.parse(json_match[0])
      data["extracted_params"] || {}
    rescue JSON::ParserError
      {}
    end
  rescue => e
    Rails.logger.error("Parameter extraction from refinement answers failed: #{e.message}")
    {}
  end

  # Enhance list items with derived details based on refinement answers
  def enhance_list_items(extracted_params)
    enhancements = {}

    begin
      # Generate enhanced descriptions for list items
      @list.list_items.each do |item|
        enhanced_description = generate_item_enhancement(item, extracted_params)

        if enhanced_description.present? && item.update(description: enhanced_description)
          enhancements[item.id] = {
            title: item.title,
            original_description: item.description_was,
            enhanced_description: enhanced_description
          }
        end
      end

      success(data: {
        enhancements: enhancements,
        extracted_params: extracted_params
      })
    rescue => e
      Rails.logger.error("List item enhancement failed: #{e.message}")
      failure(errors: [ e.message ])
    end
  end

  # Generate enhancement details for a specific item
  def generate_item_enhancement(item, extracted_params)
    llm_chat = RubyLLM::Chat.new(provider: :openai, model: "gpt-4o-mini")

    system_prompt = <<~PROMPT
      You are an assistant helping enhance list items with specific details.

      List Item: "#{item.title}"
      Current Description: "#{item.description}"

      Context from user refinement answers:
      #{extracted_params.map { |k, v| "- #{k}: #{v}" }.join("\n")}

      Generate a brief, specific enhancement to the item's description based on the context.
      The enhancement should include:
      - Specific details from the refinement answers that apply to this item
      - Actionable next steps or specifics
      - Format as a concise description (1-2 sentences max)

      Return ONLY the enhanced description text, no JSON or other formatting.
      If no specific enhancement applies to this item, return empty string.

      Examples:
      - "Book flights" with "3-day trip" context → "Book flights for 3-day trip to NYC. Check for direct flights, compare prices."
      - "Reading list" with "2-3 hours/week available" context → "Reading list (aim for 2-3 hours/week). Prioritize manageable chapters."
      - "Research hotels" with "$150/night budget" context → "Research hotels within $150/night budget in central locations."
    PROMPT

    llm_chat.add_message(role: "system", content: system_prompt)
    llm_chat.add_message(role: "user", content: "Generate enhanced description.")

    response = llm_chat.complete
    extract_response_content(response).strip
  rescue => e
    Rails.logger.error("Item enhancement generation failed: #{e.message}")
    nil
  end

  # Build user-friendly summary of refinement
  def build_refinement_summary(extracted_params, enhancements)
    summary = "Great! I've refined your list based on your preferences:\n\n"

    if extracted_params.present?
      summary += "Understood:\n"
      extracted_params.each do |key, value|
        next if value.blank? || key == "other_details"
        summary += "- #{key.humanize}: #{value}\n"
      end
      summary += "\n"
    end

    if enhancements.present?
      summary += "I've updated #{enhancements.count} items with specific details:\n"
      enhancements.each do |item_id, enhancement|
        summary += "- #{enhancement[:title]}: #{enhancement[:enhanced_description]}\n"
      end
      summary += "\nYour list is now ready to use!"
    else
      summary += "Your list is ready to use!"
    end

    summary
  end

  # Extract response content from LLM
  def extract_response_content(response)
    case response
    when String
      response
    when Hash
      response["content"] || response[:content] || response.to_s
    else
      if response.respond_to?(:content)
        content = response.content
        if content.respond_to?(:text)
          content.text
        else
          content
        end
      elsif response.respond_to?(:message)
        response.message
      elsif response.respond_to?(:text)
        response.text
      else
        response.to_s
      end
    end
  end
end
