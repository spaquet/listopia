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
