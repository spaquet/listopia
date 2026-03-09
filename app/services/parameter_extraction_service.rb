# app/services/parameter_extraction_service.rb
# Extracts parameters from natural language requests and identifies missing ones
class ParameterExtractionService < ApplicationService
  def initialize(user_message:, intent:, context:)
    @user_message = user_message
    @intent = intent
    @context = context
  end

  def call
    case @intent
    when "create_list"
      extract_list_planning_parameters
    when "create_resource"
      extract_create_parameters
    when "manage_resource"
      extract_update_parameters
    else
      success(data: { parameters: {}, missing: [] })
    end
  rescue => e
    Rails.logger.error("Parameter extraction failed: #{e.message}")
    success(data: { parameters: {}, missing: [] })
  end

  private

  def extract_list_planning_parameters
    # Use LLM to extract list planning parameters
    # Retry up to 2 times if title is not extracted
    max_retries = 2
    attempt = 0

    loop do
      attempt += 1
      llm_chat = RubyLLM::Chat.new(provider: :openai, model: "gpt-5-nano")

      system_prompt = build_list_extraction_prompt(attempt)
      llm_chat.add_message(role: "system", content: system_prompt)
      llm_chat.add_message(role: "user", content: build_list_extraction_user_message(attempt))

      response = llm_chat.complete
      response_text = extract_response_content(response)

      Rails.logger.debug("List extraction attempt #{attempt} response: #{response_text.truncate(500)}")

      # Parse the JSON response
      json_match = response_text.match(/\{[\s\S]*\}/m)

      unless json_match
        if attempt < max_retries
          Rails.logger.warn("Failed to extract JSON from LLM response (attempt #{attempt}), retrying...")
          next
        end
        # If JSON parsing fails completely after retries, use fallback title extraction
        Rails.logger.warn("Failed to extract JSON from LLM response for list planning parameters after #{max_retries} attempts, using fallback")
        fallback_title = generate_fallback_title(@user_message.content)
        return success(data: {
          resource_type: "list",
          parameters: { title: fallback_title, items: [] },
          missing: [ "category" ],
          needs_clarification: true,
          has_nested_structure: false
        })
      end

      begin
        data = JSON.parse(json_match[0])

        # Check if title is present
        if data["title"].present?
          # Title was successfully extracted, build and return result
          parameters = {
            title: data["title"],
            description: data["description"],
            category: data["category"],
            items: data["items"] || [],
            nested_lists: data["nested_lists"] || []
          }

          missing_params = data["missing"] || []

          # Remove nil values from parameters (but keep empty arrays for items)
          parameters.compact!

          return success(data: {
            resource_type: "list",
            parameters: parameters,
            missing: missing_params,
            needs_clarification: data["needs_category_clarification"] == true,
            has_nested_structure: (data["nested_lists"] || []).present?
          })
        elsif attempt < max_retries
          # Title is blank, retry with stronger emphasis
          Rails.logger.warn("LLM returned null title (attempt #{attempt}), retrying with stronger prompt...")
          next
        else
          # Title is still blank after retries, use fallback title
          Rails.logger.error("LLM failed to extract title after #{max_retries} attempts, using fallback")
          fallback_title = generate_fallback_title(@user_message.content)
          return success(data: {
            resource_type: "list",
            parameters: { title: fallback_title, items: [] },
            missing: [ "category" ],
            needs_clarification: true,
            has_nested_structure: false
          })
        end
      rescue JSON::ParserError => e
        if attempt < max_retries
          Rails.logger.warn("JSON parse error (attempt #{attempt}): #{e.message}, retrying...")
          next
        else
          # JSON parse error after retries, use fallback
          Rails.logger.error("JSON parse error after #{max_retries} attempts: #{e.message}, using fallback")
          fallback_title = generate_fallback_title(@user_message.content)
          success(data: {
            resource_type: "list",
            parameters: { title: fallback_title, items: [] },
            missing: [ "category" ],
            needs_clarification: true,
            has_nested_structure: false
          })
        end
      end
    end
  end

  # Generate a fallback title if LLM extraction fails
  def generate_fallback_title(message)
    # Extract key words from the message to create a meaningful title
    message_lower = message.downcase

    # Common patterns and their title templates
    if message_lower.include?("become") || message_lower.include?("better")
      # Extract role/position mentioned
      if message =~ /(?:better\s+)?(\w+\s+\w+)/i
        role = $1.titleize
        return "#{role} Development Plan"
      end
    end

    if message_lower.include?("learn")
      if message =~ /learn\s+(\w+)/i
        topic = $1.titleize
        return "#{topic} Learning Plan"
      end
    end

    if message_lower.include?("improve")
      if message =~ /improve\s+(?:my\s+)?(\w+)/i
        skill = $1.titleize
        return "#{skill} Improvement Plan"
      end
    end

    if message_lower.include?("plan")
      if message =~ /plan\s+(?:my\s+)?(\w+)/i
        topic = $1.titleize
        return "#{topic} Plan"
      end
    end

    # Default fallback
    "Development Plan"
  end

  # Build the system prompt for list extraction, with stronger emphasis on retries
  def build_list_extraction_prompt(attempt)
    <<~PROMPT
      Extract parameters from user request. Return ONLY valid JSON.

      {
        "title": "clear title inferred from request (REQUIRED - never null, never empty string)",
        "category": "professional" | "personal" | null,
        "description": "optional summary of what they want",
        "structure": null | "location-based" | "phase-based" | "section-based"
      }

      CRITICAL RULES:
      1. Title is REQUIRED - always provide a meaningful title
      2. If no explicit title, INFER ONE from the context
      3. Never leave title as null or empty string
      4. If user asks to "organize my expenses", title = "Expense Organization"
      5. If user asks to "learn JavaScript", title = "JavaScript Learning Plan"

      EXAMPLES:
      Input: "Plan a trip to Japan for 2 weeks"
      Output: {"title": "Japan Trip - 2 Weeks", "category": "personal", ...}

      Input: "Create a roadshow plan across 5 US cities"
      Output: {"title": "US Roadshow - 5 Cities", "category": "professional", ...}

      Input: "Give me a workout routine"
      Output: {"title": "Workout Routine", "category": "personal", ...}

      User request: "#{@user_message.content}"

      Always respond with valid JSON. ALWAYS include a title field.
    PROMPT
  end

  # Build the user message for list extraction, with stronger emphasis on retries
  def build_list_extraction_user_message(attempt)
    "Extract parameters from the request above. Return ONLY valid JSON."
  end

  # Extract the core intent from a user message for retry prompting
  def extract_core_intent(message)
    message_lower = message.downcase

    case message_lower
    when /become.*better/
      "becoming better at something"
    when /learn/
      "learning something new"
    when /improve/
      "improving a skill or area"
    when /plan/
      "planning something"
    when /organize/
      "organizing something"
    when /create.*list|create.*collection/
      "creating a list or collection"
    when /read.*book|book.*read/
      "reading books"
    else
      "planning/organizing"
    end
  end

  def extract_create_parameters
    # Use LLM to extract parameters from the message
    llm_chat = RubyLLM::Chat.new(provider: :openai, model: "gpt-5-nano")

    system_prompt = <<~PROMPT
      Extract parameters from the user's request to create a resource.

      Respond with a JSON object containing:
      - "resource_type": type of resource (user, organization, team, list, etc.)
      - "parameters": object with extracted parameters (keys should match required fields)
      - "missing": array of required parameter names that are missing

      Resource requirements:
      - User: required = [first_name, last_name, email], optional = [role, department] (password is set via invitation)
      - Organization: required = [name], optional = [description, size]
      - Team: required = [name], optional = [description, lead] (organization defaults to current: #{@context.organization.name})
      - List: required = [title], optional = [description, status] (organization defaults to current: #{@context.organization.name})

      Rules:
      1. Extract all parameters mentioned, not just required ones
      2. For users: split name into first_name and last_name. If only one name provided, that's the first_name and last_name is missing
      3. Be generous with inference for other parameters, but don't infer names
      4. Only list as "missing" if it's required and truly not provided or inferrable
      5. Normalize names to lowercase with underscores (e.g., "first name" -> "first_name")
      6. Parse emails and validate format

      User message: "#{@user_message.content}"
    PROMPT

    llm_chat.add_message(role: "system", content: system_prompt)
    llm_chat.add_message(role: "user", content: "Extract parameters from the request above.")

    response = llm_chat.complete
    response_text = extract_response_content(response)

    # Parse the JSON response
    json_match = response_text.match(/\{[\s\S]*\}/m)
    return success(data: { resource_type: nil, parameters: {}, missing: [] }) unless json_match

    begin
      data = JSON.parse(json_match[0])
      success(data: {
        resource_type: data["resource_type"],
        parameters: data["parameters"] || {},
        missing: data["missing"] || []
      })
    rescue JSON::ParserError
      success(data: { resource_type: nil, parameters: {}, missing: [] })
    end
  end

  def extract_update_parameters
    # Use LLM to extract parameters for updates/management
    llm_chat = RubyLLM::Chat.new(provider: :openai, model: "gpt-5-nano")

    system_prompt = <<~PROMPT
      Extract parameters from the user's request to update or manage a resource.

      Respond with a JSON object containing:
      - "resource_type": type of resource being managed (user, organization, team, list, etc.)
      - "resource_identifier": how to identify the resource (name, email, id, etc.)
      - "parameters": object with fields to update
      - "missing": array of required information that is missing to execute the request

      Common management operations:
      - Update user: email, role, status, department
      - Update team: name, description, lead
      - Update list: title, description, status
      - Delete resource: requires clear identification

      Rules:
      1. Extract what should be changed and what should stay the same
      2. Identify what resource is being referenced (by name, email, id, etc.)
      3. Only mark as missing if you cannot identify which resource to update
      4. Be clear about what fields are being changed vs. queried

      User message: "#{@user_message.content}"
    PROMPT

    llm_chat.add_message(role: "system", content: system_prompt)
    llm_chat.add_message(role: "user", content: "Extract parameters from the request above.")

    response = llm_chat.complete
    response_text = extract_response_content(response)

    # Parse the JSON response
    json_match = response_text.match(/\{[\s\S]*\}/m)
    return success(data: { resource_type: nil, parameters: {}, missing: [] }) unless json_match

    begin
      data = JSON.parse(json_match[0])
      success(data: {
        resource_type: data["resource_type"],
        resource_identifier: data["resource_identifier"],
        parameters: data["parameters"] || {},
        missing: data["missing"] || []
      })
    rescue JSON::ParserError
      success(data: { resource_type: nil, parameters: {}, missing: [] })
    end
  end

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
