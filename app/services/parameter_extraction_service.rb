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
      llm_chat = RubyLLM::Chat.new(provider: :openai, model: "gpt-4o-mini")

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
          missing: ["category"],
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
            missing: ["category"],
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
            missing: ["category"],
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
    base_prompt = <<~PROMPT
      Extract parameters from the user's request to create and plan a list.

      You MUST respond with a valid JSON object (and ONLY JSON, no other text) containing:
      - "resource_type": always "list"
      - "title": the main title/name for the list (inferred from context if not explicit) - REQUIRED, MUST NEVER BE NULL OR EMPTY
      - "category": one of [personal, professional] - infer from context if possible, or null if truly uncertain
      - "description": optional description of what this list is for
      - "items": array of items to add to the list (each item can be a string or object with "title" and optional "description")
      - "needs_category_clarification": boolean - true only if you cannot determine professional vs personal
      - "missing": array of required information (only ["category"] if that's unclear, otherwise empty)

      CRITICAL TITLE EXTRACTION RULES:
      1. The title MUST be extracted from the user's request - NEVER return null or empty string for title
      2. The title should reflect the main purpose/goal of what the user is asking for
      3. The title should be 3-10 words, clear and descriptive
      4. If the user's intent is implicit (e.g., "I want to become a better X"), create a title like "X Development Plan" or "X Improvement Plan"
      5. Extract relevant keywords from the request and combine them into a coherent title

      Examples of proper title extraction:
      - User: "plan my business trip to New York next week" → Title: "New York Business Trip"
      - User: "organize my grocery shopping" → Title: "Grocery Shopping"
      - User: "i want to become a better marketing manager. provide me with 5 books to read and a plan to improve in 6 weeks." → Title: "Marketing Manager Development Plan"
      - User: "create a project plan for my startup" → Title: "Startup Project Plan"
      - User: "help me learn Python" → Title: "Python Learning Plan"
      - User: "give me a workout routine for 8 weeks" → Title: "8-Week Workout Routine"
      - User: "plan our company roadshow across 5 US cities" → Title: "US Company Roadshow"

      General Rules:
      1. ALWAYS infer a meaningful title - the user's intent should inform the title
      2. INFER list items from the request context (e.g., "trip to New York" could include hotel, flights, itinerary, etc.)
      3. For category: ALWAYS try to infer from context (business = professional, personal = personal, learning = personal, etc.)
      4. Category values must be: "personal", "professional", or null (if truly uncertain)
      5. Only set needs_category_clarification to true if you TRULY CANNOT determine professional vs personal
         - Examples where you CAN infer:
           * "I want to become a better marketing manager" → professional (career development)
           * "Plan my vacation" → personal
           * "Create a workout routine" → personal
           * "Marketing director development plan" → professional (career goal)
           * "Learn Python" → personal (self-improvement)
      6. If you infer the category successfully, set needs_category_clarification to false
      7. If category cannot be inferred, set it to null and add "category" to missing array, AND set needs_category_clarification to true
      8. Be generous in inferring items - think about what tasks/steps would be involved in achieving this goal
      9. DETECT NESTED STRUCTURES: Look for multi-level lists or hierarchical patterns
         - Location-based: "cities: New York, Chicago, Boston" with shared tasks per location
         - Phase-based: "Before roadshow", "During roadshow", "After roadshow" with tasks per phase
         - Week-based: "Week 1", "Week 2", etc. with tasks per week
         - Set-based: Groups of items that should be sub-lists
      9. For nested lists, structure as:
         {
           "title": "Main title",
           "items": [...],
           "nested_lists": [
             {
               "title": "Sub-list title (e.g., New York)",
               "items": ["task for this location", ...]
             },
             ...
           ]
         }

      User message: "#{@user_message.content}"
    PROMPT

    if attempt > 1
      base_prompt + <<~PROMPT

        **RETRY ATTEMPT #{attempt}**: The previous extraction had a missing or null title.

        You MUST ensure the title field is never null. If you previously returned null for title,
        analyze the user's request more carefully and extract a meaningful title that describes
        what the user is trying to accomplish.

        The user is asking for: #{extract_core_intent(@user_message.content)}

        Use this core intent to create a descriptive title if you haven't already.
      PROMPT
    else
      base_prompt
    end
  end

  # Build the user message for list extraction, with stronger emphasis on retries
  def build_list_extraction_user_message(attempt)
    if attempt > 1
      "Extract list planning parameters from the request above. CRITICAL: You MUST provide a non-null title. If you returned null before, extract the title now from the user's intent."
    else
      "Extract list planning parameters from the request above. IMPORTANT: Always include a title, never return null for title."
    end
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
    llm_chat = RubyLLM::Chat.new(provider: :openai, model: "gpt-4o-mini")

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
    llm_chat = RubyLLM::Chat.new(provider: :openai, model: "gpt-4o-mini")

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
