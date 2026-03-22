# app/services/parameter_mapper_service.rb
# Maps user answers to structured parameters for planning context
# Handles extraction from pre-creation planning answers and user input

class ParameterMapperService < ApplicationService
  def initialize(planning_context, answers_hash = nil)
    @planning_context = planning_context
    @answers = answers_hash || {}
  end

  def call
    begin
      # If we have pre-creation answers, extract parameters from them
      if @answers.present?
        parameters = extract_from_answers(@answers)
      else
        # Use existing parameters
        parameters = @planning_context.parameters || {}
      end

      # Enrich with domain-specific parameter extraction
      enriched_params = enrich_parameters(parameters)

      # Update planning context with extracted parameters
      @planning_context.add_parameters(enriched_params)

      success(data: {
        parameters: enriched_params,
        planning_context: @planning_context
      })
    rescue StandardError => e
      Rails.logger.error("ParameterMapperService error: #{e.class} - #{e.message}")
      failure(errors: [ e.message ])
    end
  end

  private

  def extract_from_answers(answers_hash)
    parameters = {}

    # Common parameters
    parameters[:title] = answers_hash["title"] if answers_hash["title"].present?
    parameters[:description] = answers_hash["description"] if answers_hash["description"].present?
    parameters[:timeline] = answers_hash["timeline"] if answers_hash["timeline"].present?
    parameters[:budget] = answers_hash["budget"] if answers_hash["budget"].present?

    # Location-based parameters
    if answers_hash["locations"].present?
      locations = answers_hash["locations"]
      parameters[:locations] = locations.is_a?(String) ? locations.split(",").map(&:strip) : locations
    end

    # Dates
    parameters[:start_date] = answers_hash["start_date"] if answers_hash["start_date"].present?
    parameters[:end_date] = answers_hash["end_date"] if answers_hash["end_date"].present?

    # Categories/types
    parameters[:category] = answers_hash["category"] if answers_hash["category"].present?
    parameters[:type] = answers_hash["type"] if answers_hash["type"].present?

    # People/resources
    parameters[:team_size] = answers_hash["team_size"] if answers_hash["team_size"].present?
    parameters[:participants] = answers_hash["participants"] if answers_hash["participants"].present?

    parameters
  end

  def enrich_parameters(base_params)
    parameters = base_params.dup

    # Use LLM to intelligently detect the best subdivision strategy for this specific use case
    subdivision_result = detect_subdivision_strategy(parameters)

    if subdivision_result.success?
      subdivision_data = subdivision_result.data
      parameters[:subdivision_type] = subdivision_data[:type]
      parameters[:subdivision_count] = subdivision_data[:count]
      parameters[:subdivision_key] = subdivision_data[:key]  # e.g., "locations", "books", "modules", "topics"
    else
      # Fallback to simple rules if LLM detection fails
      parameters[:subdivision_type] = "none"
    end

    # Classify complexity if not already done
    parameters[:domain_hint] = @planning_context.planning_domain if @planning_context.planning_domain.present?

    parameters
  end

  def detect_subdivision_strategy(parameters)
    begin
      Rails.logger.info("detect_subdivision_strategy - Starting with parameters: #{parameters.keys.inspect}")

      # Check if there are actual subdivision candidates
      subdivision_candidates = {
        locations: parameters[:locations],
        books: parameters[:books],
        topics: parameters[:topics],
        modules: parameters[:modules],
        items: parameters[:items],
        phases: parameters[:timeline],
        teams: parameters[:team_members]
      }.reject { |_k, v| v.blank? }

      Rails.logger.info("detect_subdivision_strategy - Found candidates: #{subdivision_candidates.keys.inspect}")

      return success(data: { type: "none", count: 0, key: nil }) if subdivision_candidates.empty?

      # Build prompt for LLM to determine best subdivision strategy
      prompt = build_subdivision_detection_prompt(parameters, subdivision_candidates)

      response = detect_via_llm(prompt)
      Rails.logger.info("detect_subdivision_strategy - LLM response: #{response.inspect}")

      return failure(errors: ["Failed to detect subdivision"]) if response.blank?

      # Parse LLM response
      parsed = JSON.parse(response) rescue nil
      Rails.logger.info("detect_subdivision_strategy - Parsed response: #{parsed.inspect}")

      return failure(errors: ["Invalid subdivision response"]) unless parsed.is_a?(Hash)

      success(data: {
        type: parsed["type"] || "none",
        count: parsed["count"] || 0,
        key: parsed["key"] || nil
      })
    rescue StandardError => e
      Rails.logger.error("detect_subdivision_strategy error: #{e.class} - #{e.message}")
      failure(errors: [e.message])
    end
  end

  def build_subdivision_detection_prompt(parameters, candidates)
    domain = @planning_context.planning_domain || "general"
    title = @planning_context.request_content || ""

    <<~PROMPT
      Based on this planning request, determine the best way to subdivide the list.

      Domain: #{domain}
      Title: #{title}
      Category: #{parameters[:category]}

      Available subdivision candidates:
      #{candidates.map { |k, v| "- #{k}: #{v.is_a?(Array) ? v.length : 'present'}" }.join("\n")}

      Return JSON with:
      {
        "type": "locations" | "books" | "topics" | "modules" | "items" | "phases" | "teams" | "none",
        "count": number of subdivisions,
        "key": the parameter key that contains the subdivision data
      }

      Choose the most natural subdivision for this use case:
      - For events/travel: use "locations"
      - For courses/learning: use "modules" or "topics"
      - For reading: use "books"
      - For projects: use "modules" or "phases"
      - For cooking/recipes: use "items"
      - For product: use "phases" or "modules"

      Return ONLY valid JSON.
    PROMPT
  end

  def detect_via_llm(prompt)
    begin
      llm_chat = RubyLLM::Chat.new(
        provider: :openai,
        model: "gpt-5-nano"
      )

      llm_chat.add_message(
        role: "system",
        content: "You are a planning expert. Determine the best subdivision strategy for organizing a list based on the context provided."
      )

      llm_chat.add_message(role: "user", content: prompt)

      response = llm_chat.complete

      # Extract text from response
      case response
      when String
        response
      when Hash
        response["content"] || response[:content] || response.to_s
      else
        # Handle RubyLLM::Message object
        content = response&.content
        if content.is_a?(String)
          content
        else
          content&.text || response.to_s
        end
      end
    rescue StandardError => e
      Rails.logger.error("detect_via_llm error: #{e.class} - #{e.message}")
      nil
    end
  end

  def infer_phase_count(parameters)
    # Try to infer number of phases from timeline description
    timeline = parameters[:timeline].to_s.downcase

    case timeline
    when /week/
      1
    when /month/
      4
    when /quarter|3.month/
      3
    when /year|6.month/
      4
    when /\d+\s*(?:week|month|day)/
      # Extract number if present
      match = timeline.match(/(\d+)\s*(?:week|month|day)/)
      match[1].to_i if match
    else
      2 # Default to 2 phases
    end
  end
end
