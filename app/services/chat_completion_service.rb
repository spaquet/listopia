# app/services/chat_completion_service.rb
#
# Service for handling chat message processing using RubyLLM
# Integrates with RubyLLM 1.9+ for unified LLM provider support
# Supports OpenAI, Anthropic Claude, Google Gemini, and more
#
# Features:
# - Tool/function calling for managing users, teams, organizations, lists
# - Smart routing to existing app pages instead of chat responses
# - Prompt injection detection and content moderation
# - Full message history context for conversation

class ChatCompletionService < ApplicationService
  def initialize(chat, user_message, context = nil)
    @chat = chat
    @user_message = user_message
    @context = context || ChatContext.new(
      chat: chat,
      user: user_message.user,
      organization: chat.organization,
      location: :dashboard
    )
  end

  def call
    return failure(errors: [ "Chat not found" ]) unless @chat
    return failure(errors: [ "User message not found" ]) unless @user_message

    begin
      # Use AI to detect user intent
      intent_result = AiIntentRouterService.new(
        user_message: @user_message,
        chat: @chat,
        user: @context.user,
        organization: @context.organization
      ).call

      # If intent is to navigate to a page, do that instead of LLM response
      if intent_result.success? && intent_result.data[:intent] == "navigate_to_page"
        return handle_navigation_intent(intent_result.data)
      end

      # Check for missing parameters in resource creation/management requests
      intent = intent_result.success? ? intent_result.data[:intent] : nil
      if intent.in?(["create_resource", "manage_resource"])
        parameter_check = check_parameters_for_intent(intent)
        return parameter_check if parameter_check
      end

      # Get or determine the model to use
      model = @chat.metadata["model"] || default_model

      # Build message history for context
      message_history = build_message_history(model)

      # Get system prompt based on context
      system_prompt = enhanced_system_prompt

      # Get available tools for the LLM
      tools_service = LlmToolsService.new(
        user: @context.user,
        organization: @context.organization,
        chat_context: @context
      )
      tools_result = tools_service.call
      tools = tools_result.success? ? tools_result.data : []

      # Call RubyLLM with tool support
      response = call_llm_with_tools(model, system_prompt, message_history, tools)

      return failure(errors: [ "LLM call failed" ]) if response.blank?

      # Handle tool calls if present
      if response.is_a?(Hash) && response[:type] == :tool_call
        return handle_tool_call(response)
      end

      # Create assistant message with the response
      assistant_message = Message.create_assistant(
        chat: @chat,
        content: response.is_a?(String) ? response : response.to_s
      )

      # Update chat with last message time
      @chat.update(last_message_at: Time.current)

      success(data: assistant_message)
    rescue StandardError => e
      Rails.logger.error("Chat completion failed: #{e.class} - #{e.message}")
      failure(errors: [ e.message ], message: "Failed to generate response")
    end
  end

  private

  # Check for missing parameters in resource creation/management
  def check_parameters_for_intent(intent)
    param_result = ParameterExtractionService.new(
      user_message: @user_message,
      intent: intent,
      context: @context
    ).call

    return nil unless param_result.success?

    data = param_result.data
    missing_params = data[:missing] || []
    resource_type = data[:resource_type]

    # Filter out organization_id from missing params for teams/lists since it defaults to current org
    if resource_type.in?(["team", "list"])
      missing_params = missing_params.reject { |param| param.downcase.include?("organization") }
    end

    # If there are missing parameters, ask the user for them
    if missing_params.present?
      return handle_missing_parameters(data, missing_params)
    end

    # Parameters are complete, return nil to continue normal flow
    nil
  end

  # Create a message asking for missing parameters
  def handle_missing_parameters(param_data, missing_params)
    resource_type = param_data[:resource_type] || "resource"

    # Build a friendly message asking for missing parameters
    message_content = build_missing_parameter_message(resource_type, missing_params, param_data[:parameters] || {})

    # Create assistant message with the request
    assistant_message = Message.create_assistant(
      chat: @chat,
      content: message_content
    )

    @chat.update(last_message_at: Time.current)

    success(data: assistant_message)
  end

  # Build a user-friendly message asking for missing parameters
  def build_missing_parameter_message(resource_type, missing_params, extracted_params)
    # Only show parameters that have non-empty values
    present_params = extracted_params.select { |_k, v| v.present? }
    existing = if present_params.present?
                 " I found: #{present_params.map { |k, v| "#{k}: #{v}" }.join(', ')}."
               else
                 ""
               end

    missing_list = missing_params.map { |param| "- #{param}" }.join("\n")

    case resource_type.downcase
    when "user"
      "I'd like to help you create a user.#{existing} To proceed, I need the following information:\n#{missing_list}"
    when "organization", "org"
      "I'd like to help you create an organization.#{existing} To proceed, I need the following information:\n#{missing_list}"
    when "team"
      "I'd like to help you create a team.#{existing} To proceed, I need the following information:\n#{missing_list}"
    when "list"
      "I'd like to help you create a list.#{existing} To proceed, I need the following information:\n#{missing_list}"
    else
      "I'd like to help you create a #{resource_type}.#{existing} To proceed, I need the following information:\n#{missing_list}"
    end
  end

  # Handle navigation intent detected by AI
  def handle_navigation_intent(intent_data)
    description = intent_data[:description]

    # Map common navigation intents to app pages
    path = map_intent_to_path(description)

    return failure(errors: [ "Could not determine page to navigate to" ]) unless path

    # Create and save a special navigation message
    nav_message = Message.create!(
      chat: @chat,
      role: :assistant,
      content: "I'll help you with that. Opening the relevant page...",
      template_type: "navigation",
      metadata: {
        navigation: {
          path: path,
          filters: {}
        }
      }
    )

    # Mark as navigation so frontend knows to redirect
    @chat.update(last_message_at: Time.current)

    success(data: nav_message)
  end

  # Map intent descriptions to app page paths
  def map_intent_to_path(description)
    description_lower = description.downcase

    # Users management
    return "/admin/users" if description_lower.include?("user")
    return "/admin/organizations" if description_lower.include?("organization") || description_lower.include?("org")
    return "/organizations/#{@context.organization.id}/teams" if description_lower.include?("team")

    # Lists management
    return "/lists" if description_lower.include?("list")

    # Admin dashboard
    return "/admin" if description_lower.include?("dashboard") || description_lower.include?("admin")

    nil
  end

  # Handle tool calls from the LLM
  def handle_tool_call(tool_call_data)
    tool_name = tool_call_data[:tool_name]
    tool_input = tool_call_data[:tool_input]

    # Execute the tool
    executor = LlmToolExecutorService.new(
      tool_name: tool_name,
      tool_input: tool_input,
      user: @context.user,
      organization: @context.organization,
      chat_context: @context
    )

    result = executor.call

    if result.failure?
      error_message = Message.create_templated(
        chat: @chat,
        template_type: "error",
        template_data: {
          message: "I encountered an issue",
          details: result.errors.first
        }
      )
      return success(data: error_message)
    end

    tool_result = result.data

    # Create and save a message with the tool result
    tool_message = Message.create!(
      chat: @chat,
      role: :assistant,
      content: format_tool_result(tool_result),
      template_type: tool_result[:type],
      metadata: {
        tool_call: tool_name,
        tool_result: tool_result
      }
    )

    @chat.update(last_message_at: Time.current)

    success(data: tool_message)
  end

  # Format tool result for display
  def format_tool_result(result)
    case result[:type]
    when "navigation"
      "Opening #{result[:message]}"
    when "list"
      "Found #{result[:total_count]} #{result[:resource_type].pluralize.downcase}."
    when "resource"
      "Successfully #{result[:action]} #{result[:resource_type]}."
    when "search_results"
      "Found #{result[:total_count]} results for '#{result[:query]}'."
    else
      "Operation completed successfully."
    end
  end

  # Determine the default LLM model and provider
  def default_model
    "gpt-4o-mini"  # OpenAI default - can be configured per organization/user
  end

  # Parse model string to extract provider and model name
  # Examples: "gpt-4o-mini", "claude-3-sonnet", "gemini-pro"
  def parse_model(model_string)
    case model_string
    when /^gpt-/
      { provider: :openai, model: model_string }
    when /^claude-/
      { provider: :anthropic, model: model_string }
    when /^gemini-/
      { provider: :google, model: model_string }
    when /^llama-/
      { provider: :fireworks, model: model_string }
    else
      { provider: :openai, model: model_string }
    end
  end

  # Build message history from recent messages in the chat
  def build_message_history(model)
    recent_messages = @chat.messages.ordered.last(20)

    # Only include messages with content and that are user/assistant roles
    messages = recent_messages.select { |msg| msg.content.present? && ['user', 'assistant'].include?(msg.role) }.map do |msg|
      {
        role: msg.role.to_s,
        content: msg.content
      }
    end

    # Add current user message if not already in history
    messages.push({
      role: "user",
      content: @user_message.content
    })

    messages
  end

  # Call RubyLLM with the provided messages
  def call_llm(model, system_prompt, message_history)
    model_config = parse_model(model)

    # Create RubyLLM::Chat instance
    llm_chat = RubyLLM::Chat.new(
      provider: model_config[:provider],
      model: model_config[:model]
    )

    # Set additional options if supported
    llm_chat.temperature = 0.7 if llm_chat.respond_to?(:temperature=)
    llm_chat.max_tokens = 2000 if llm_chat.respond_to?(:max_tokens=)

    # Add system prompt
    if system_prompt.present?
      llm_chat.add_message(role: "system", content: system_prompt)
    end

    # Add message history (excluding current message since we'll add separately)
    message_history[0...-1].each do |msg|
      llm_chat.add_message(role: msg[:role], content: msg[:content])
    end

    # Add current user message
    llm_chat.add_message(role: "user", content: @user_message.content)

    # Get completion
    response = llm_chat.complete

    # Extract response content
    extract_response_content(response)
  rescue => e
    Rails.logger.error("RubyLLM error: #{e.class} - #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    nil
  end

  # Extract the assistant's response from RubyLLM response object
  def extract_response_content(response)
    Rails.logger.debug("RubyLLM response class: #{response.class}")
    Rails.logger.debug("RubyLLM response: #{response.inspect}")

    case response
    when String
      response
    when Hash
      response["content"] || response[:content] || response.to_s
    else
      # Handle RubyLLM::Message with RubyLLM::Content
      if response.respond_to?(:content)
        content = response.content
        # If content is a RubyLLM::Content object with text attribute
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

  # Call RubyLLM with tool support
  def call_llm_with_tools(model, system_prompt, message_history, tools)
    model_config = parse_model(model)

    # Create RubyLLM::Chat instance
    llm_chat = RubyLLM::Chat.new(
      provider: model_config[:provider],
      model: model_config[:model]
    )

    # Set additional options
    llm_chat.temperature = 0.7 if llm_chat.respond_to?(:temperature=)
    llm_chat.max_tokens = 2000 if llm_chat.respond_to?(:max_tokens=)

    # Add system prompt with tool instructions
    enhanced_prompt = system_prompt + "\n\nYou have access to tools to help manage the app. " \
                     "When the user asks you to show a list of users, teams, or organizations, " \
                     "or to perform actions like creating or updating resources, " \
                     "use the appropriate tool to accomplish the task."

    llm_chat.add_message(role: "system", content: enhanced_prompt) if enhanced_prompt.present?

    # Add message history
    message_history[0...-1].each do |msg|
      llm_chat.add_message(role: msg[:role], content: msg[:content])
    end

    # Add current user message
    llm_chat.add_message(role: "user", content: @user_message.content)

    # Set tools if the LLM supports them
    if llm_chat.respond_to?(:tools=) && tools.present?
      llm_chat.tools = tools
    end

    # Get completion with tool support
    response = llm_chat.complete

    # Check if response includes tool calls
    # Handle both Hash responses and RubyLLM::Message objects
    tool_calls = if response.is_a?(Hash)
                   response[:tool_calls]
                 elsif response.respond_to?(:tool_calls)
                   response.tool_calls
                 end

    if tool_calls.present?
      # Return first tool call for execution
      tool_call = tool_calls.first
      {
        type: :tool_call,
        tool_name: tool_call[:name] || tool_call["name"] || tool_call.name,
        tool_input: tool_call[:arguments] || tool_call["arguments"] || tool_call.arguments || {}
      }
    else
      # Return text response
      extract_response_content(response)
    end
  rescue => e
    Rails.logger.error("RubyLLM error: #{e.class} - #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    nil
  end

  # Build an enhanced system prompt that explains available tools and features
  def enhanced_system_prompt
    base_prompt = @context.system_prompt

    # Add tool instructions
    tool_instructions = <<~PROMPT
      You can help users by:
      1. Answering questions about their data
      2. Navigating them to specific pages (when they ask to "show all users", "list organizations", etc.)
      3. Creating new resources (users, teams, lists) when requested
      4. Updating existing resources (changing roles, statuses, etc.)
      5. Searching for information across the app

      When a user asks to view something like "show me active users" or "list all organizations",
      recognize their intent and help them navigate to the appropriate page or retrieve the information.
    PROMPT

    "#{base_prompt}\n\n#{tool_instructions}"
  end
end
