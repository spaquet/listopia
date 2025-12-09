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
    llm_chat = RubyLLM::Chat.new(provider: :openai, model: "gpt-4o-mini")

    system_prompt = <<~PROMPT
      Extract parameters from the user's request to create and plan a list.

      Respond with a JSON object containing:
      - "resource_type": always "list"
      - "title": the main title/name for the list (inferred from context if not explicit)
      - "category": one of [personal, professional] - infer from context if possible
      - "description": optional description of what this list is for
      - "items": array of items to add to the list (each item should have "title" and optional "description")
      - "needs_category_clarification": boolean - true if you cannot determine professional vs personal
      - "missing": array of required information (only ["category"] if that's unclear, otherwise empty)

      Examples:
      1. "plan my business trip to New York next week"
         -> title: "New York Business Trip", category: "professional", items: inferred from context

      2. "organize my grocery shopping"
         -> title: "Grocery Shopping", category: "personal", items: common items for grocery shopping

      3. "create a project plan for my startup"
         -> title: "Startup Project Plan", category: "professional", items: inferred phases/tasks

      Rules:
      1. INFER the list title from the user's request if not explicitly stated
      2. INFER list items from the request context (e.g., "trip to New York" could include hotel, flights, itinerary, etc.)
      3. For category: ALWAYS try to infer from context (business = professional, personal = personal, shopping = personal, etc.)
      4. Category values must be: "personal" or "professional"
      5. Only set needs_category_clarification to true if you truly cannot determine if it's professional or personal
      6. If category cannot be inferred, set it to null and add "category" to missing array
      7. Be generous in inferring items - think about what tasks/steps would be involved
      8. DETECT NESTED STRUCTURES: Look for multi-level lists or hierarchical patterns
         - Location-based: "cities: New York, Chicago, Boston" with shared tasks per location
         - Phase-based: "Before roadshow", "During roadshow", "After roadshow" with tasks per phase
         - Set-based: Groups of items that should be sub-lists (e.g., per-location tasks, per-team tasks)
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

    llm_chat.add_message(role: "system", content: system_prompt)
    llm_chat.add_message(role: "user", content: "Extract list planning parameters from the request above.")

    response = llm_chat.complete
    response_text = extract_response_content(response)

    # Parse the JSON response
    json_match = response_text.match(/\{[\s\S]*\}/m)
    return success(data: { resource_type: "list", parameters: {}, missing: [], needs_clarification: false }) unless json_match

    begin
      data = JSON.parse(json_match[0])

      # Build parameters object
      parameters = {
        title: data["title"],
        description: data["description"],
        category: data["category"],
        items: data["items"] || [],
        nested_lists: data["nested_lists"] || []
      }

      # Remove nil values
      parameters.compact!

      success(data: {
        resource_type: "list",
        parameters: parameters,
        missing: data["missing"] || [],
        needs_clarification: data["needs_category_clarification"] == true,
        has_nested_structure: (data["nested_lists"] || []).present?
      })
    rescue JSON::ParserError
      success(data: { resource_type: "list", parameters: {}, missing: [], needs_clarification: false })
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
