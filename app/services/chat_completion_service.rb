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
      # Check if we're in a list refinement stage and user is answering questions
      if pending_list_refinement?
        refinement_result = handle_list_refinement_response
        return refinement_result if refinement_result
      end

      # Check if we're continuing a pending resource creation FIRST
      # This takes precedence over new intent detection
      if pending_resource_creation?
        continuation_result = handle_resource_creation_continuation
        return continuation_result if continuation_result
      end

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
      if intent.in?([ "create_list", "create_resource", "manage_resource" ])
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
    # SAFETY CHECK: Detect if this was misclassified as user creation
    # When intent is "create_resource", do additional validation
    if intent == "create_resource"
      if looks_like_planning_request(@user_message.content)
        # Reclassify as create_list
        intent = "create_list"
      end
    end

    param_result = ParameterExtractionService.new(
      user_message: @user_message,
      intent: intent,
      context: @context
    ).call

    return nil unless param_result.success?

    data = param_result.data
    missing_params = data[:missing] || []
    resource_type = data[:resource_type]
    needs_clarification = data[:needs_clarification]

    Rails.logger.info("ChatCompletionService#check_parameters_for_intent - Intent: #{intent}, Data: #{data.inspect}")

    # Filter out organization_id from missing params for teams/lists since it defaults to current org
    if resource_type.in?([ "team", "list" ])
      missing_params = missing_params.reject { |param| param.downcase.include?("organization") }
    end

    # For list creation, ask to clarify category if needed
    if intent == "create_list" && needs_clarification
      Rails.logger.info("ChatCompletionService#check_parameters_for_intent - Returning category clarification")
      return handle_list_category_clarification(data)
    end

    # If there are missing parameters, ask the user for them
    if missing_params.present?
      Rails.logger.info("ChatCompletionService#check_parameters_for_intent - Missing params: #{missing_params.inspect}, Returning missing parameters handler")
      return handle_missing_parameters(data, missing_params)
    end

    # Parameters are complete!
    # For list and resource creation, proceed with creation
    if intent == "create_list"
      Rails.logger.info("ChatCompletionService#check_parameters_for_intent - Proceeding with list creation, parameters: #{(data[:parameters] || {}).inspect}")
      return handle_list_creation("list", data[:parameters] || {})
    elsif intent == "create_resource"
      Rails.logger.info("ChatCompletionService#check_parameters_for_intent - Proceeding with resource creation")
      return handle_resource_creation(data[:resource_type] || "resource", data[:parameters] || {})
    end

    # For other intents with complete parameters, return nil to continue normal flow
    nil
  end

  # Detect if a message that was classified as user creation is actually planning
  def looks_like_planning_request(message)
    message_lower = message.downcase

    # Planning/development indicators - broader set of keywords
    planning_keywords = [
      "plan", "improve", "learn", "read", "book", "course",
      "guide", "list", "collection", "routine", "schedule",
      "strategy", "roadmap", "roadshow", "itinerary",
      "skill", "develop", "become better", "growth", "program",
      "framework", "methodology", "curriculum", "checklist",
      "guide", "tips", "advice", "suggest", "recommend",
      "become", "better", "help me", "give me",
      "create a plan", "professional development", "self-improvement",
      "learning", "coaching", "mentoring", "improving",
      "effective", "manager", "leader", "marketing",
      "business", "personal", "career", "goals"
    ]

    # Check if message contains planning keywords
    has_planning_keyword = planning_keywords.any? { |kw| message_lower.include?(kw) }

    # User creation indicators - very specific and explicit
    user_creation_keywords = [
      "create user", "add user", "invite", "register",
      "new member", "add member", "create account"
    ]

    # User-specific patterns (looking for email or explicit user mentions)
    has_explicit_user_creation = user_creation_keywords.any? { |kw| message_lower.include?(kw) } ||
                                  message_lower.match?(/\b[\w\.-]+@[\w\.-]+\.\w+\b/)  # Email pattern

    # If it has planning keywords but no explicit user creation request, it's likely planning
    has_planning_keyword && !has_explicit_user_creation
  end

  # Ask user to clarify if list is professional or personal
  def handle_list_category_clarification(param_data)
    @chat.metadata ||= {}
    @chat.metadata["pending_resource_creation"] = {
      resource_type: "list",
      extracted_params: param_data[:parameters] || {},
      missing_params: [ "category" ],
      intent: "create_list",
      needs_clarification: true
    }
    @chat.save

    parameters = param_data[:parameters] || {}
    title = parameters["title"] || "your list"

    message_content = "I'd like to help you create a list called \"#{title}\". " \
                      "Is this for work/professional purposes or for personal use? " \
                      "Please let me know so I can organize it appropriately."

    assistant_message = Message.create_assistant(
      chat: @chat,
      content: message_content
    )

    @chat.update(last_message_at: Time.current)

    success(data: assistant_message)
  end

  # Create a message asking for missing parameters
  def handle_missing_parameters(param_data, missing_params)
    resource_type = param_data[:resource_type] || "resource"

    # Store the pending resource creation in chat metadata for continuation
    @chat.metadata ||= {}
    @chat.metadata["pending_resource_creation"] = {
      resource_type: resource_type,
      extracted_params: param_data[:parameters] || {},
      missing_params: missing_params,
      intent: "create_resource"
    }
    @chat.save

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

  # Check if we're in a list refinement state
  def pending_list_refinement?
    @chat.metadata&.dig("pending_list_refinement").present?
  end

  # Handle user's response to refinement questions
  def handle_list_refinement_response
    refinement_data = @chat.metadata["pending_list_refinement"]
    return nil unless refinement_data

    list_id = refinement_data["list_id"]
    list = List.find_by(id: list_id)
    return nil unless list

    # Process the refinement answers
    processor = ListRefinementProcessorService.new(
      list: list,
      user_answers: @user_message.content,
      refinement_context: refinement_data["context"],
      context: @context
    )

    result = processor.call

    if result.success?
      # Clear refinement state
      @chat.metadata.delete("pending_list_refinement")
      @chat.save

      # Create success message with refinement summary
      message_content = result.data[:message]

      assistant_message = Message.create_assistant(
        chat: @chat,
        content: message_content
      )

      @chat.update(last_message_at: Time.current)

      success(data: assistant_message)
    else
      # If processing fails, ask user to try again
      message_content = "I had trouble understanding those details. Could you provide a bit more information? " \
                       "For example: #{refinement_data[:example_format]}"

      assistant_message = Message.create_assistant(
        chat: @chat,
        content: message_content
      )

      @chat.update(last_message_at: Time.current)

      success(data: assistant_message)
    end
  end

  # Check if we're in a pending resource creation state
  def pending_resource_creation?
    @chat.metadata&.dig("pending_resource_creation").present?
  end

  # Handle continuation of resource creation when user provides more parameters
  def handle_resource_creation_continuation
    pending = @chat.metadata["pending_resource_creation"]
    return nil unless pending

    # SAFETY CHECK: If we're in a resource creation continuation but the user's new message
    # looks like a planning request, cancel the continuation and re-detect intent
    if pending["resource_type"] == "user" && looks_like_planning_request(@user_message.content)
      # Clear the pending state and let normal intent detection take over
      @chat.metadata.delete("pending_resource_creation")
      @chat.save
      return nil  # This will allow the flow to continue to normal intent detection
    end

    # For list creation, when we're asking for category clarification,
    # don't re-extract parameters - just use the category from the user response
    if pending["resource_type"] == "list" && pending["missing_params"]&.include?("category")
      # Check if user response contains a category indicator
      response_lower = @user_message.content.downcase
      inferred_category = if response_lower.include?("professional") || response_lower.include?("work") || response_lower.include?("business")
                            "professional"
                          elsif response_lower.include?("personal")
                            "personal"
                          else
                            nil
                          end

      if inferred_category
        # Keep all previously extracted params and just add the category
        merged_params = pending["extracted_params"].merge({ "category" => inferred_category })
        new_params = { "category" => inferred_category }
        resource_type = pending["resource_type"]
        remaining_missing = (pending["missing_params"] || []).reject { |param| param == "category" }

        if remaining_missing.blank?
          # All parameters are now complete!
          @chat.metadata.delete("pending_resource_creation")
          @chat.save
          return handle_list_creation(resource_type, merged_params)
        end
      end
    end

    # Extract parameters from the new user message
    param_result = ParameterExtractionService.new(
      user_message: @user_message,
      intent: pending["intent"],
      context: @context
    ).call

    return nil unless param_result.success?

    new_params = param_result.data[:parameters] || {}
    resource_type = pending["resource_type"]

    # Merge new parameters with previously extracted ones
    merged_params = pending["extracted_params"].merge(new_params)

    # Update missing params - remove any that are now provided
    # Convert all keys to strings for consistent comparison
    merged_keys = merged_params.keys.map(&:to_s)
    remaining_missing = (pending["missing_params"] || []).reject do |param|
      param_str = param.to_s.downcase
      # Check if any merged key matches this missing parameter (case-insensitive)
      merged_keys.any? { |key| key.downcase == param_str && merged_params[key].present? }
    end

    # If still missing parameters, ask for them
    if remaining_missing.present?
      @chat.metadata["pending_resource_creation"] = {
        resource_type: resource_type,
        extracted_params: merged_params,
        missing_params: remaining_missing,
        intent: "create_resource"
      }
      @chat.save

      message_content = build_missing_parameter_message(resource_type, remaining_missing, merged_params)
      assistant_message = Message.create_assistant(
        chat: @chat,
        content: message_content
      )
      @chat.update(last_message_at: Time.current)
      return success(data: assistant_message)
    end

    # All parameters collected! Clear pending state and proceed with creation
    @chat.metadata.delete("pending_resource_creation")
    @chat.save

    # Create the resource with all collected parameters
    if resource_type == "list"
      handle_list_creation(resource_type, merged_params)
    else
      handle_resource_creation(resource_type, merged_params)
    end
  end

  # Handle the actual resource creation
  def handle_resource_creation(resource_type, parameters)
    # Use ChatResourceCreatorService to actually create the resource
    creator = ChatResourceCreatorService.new(
      resource_type: resource_type,
      parameters: parameters,
      created_by_user: @context.user,
      created_in_organization: @context.organization
    )

    result = creator.call

    if result.failure?
      # If creation fails, report the error
      message_content = "I encountered an issue creating the #{resource_type}:\n"
      result.errors.each do |error|
        message_content += "- #{error}\n"
      end

      assistant_message = Message.create_assistant(
        chat: @chat,
        content: message_content
      )
    else
      # Success - report what was created
      creation_data = result.data
      message_content = creation_data[:message]

      assistant_message = Message.create_assistant(
        chat: @chat,
        content: message_content
      )
    end

    @chat.update(last_message_at: Time.current)

    success(data: assistant_message)
  end

  # Handle list creation with items
  def handle_list_creation(resource_type, parameters)
    # Log parameters for debugging
    Rails.logger.info("ChatCompletionService#handle_list_creation - Resource type: #{resource_type}, Parameters: #{parameters.inspect}")

    # Create list using ChatResourceCreatorService
    creator = ChatResourceCreatorService.new(
      resource_type: resource_type,
      parameters: parameters,
      created_by_user: @context.user,
      created_in_organization: @context.organization
    )

    result = creator.call

    if result.failure?
      # If creation fails, report the error
      message_content = "I encountered an issue creating the list:\n"
      result.errors.each do |error|
        message_content += "- #{error}\n"
      end

      assistant_message = Message.create_assistant(
        chat: @chat,
        content: message_content
      )
    else
      # Success - report what was created
      creation_data = result.data
      list = creation_data[:resource]
      items_count = creation_data[:items_created] || 0
      sublists_count = creation_data[:sublists_created] || 0

      message_content = creation_data[:message]

      # Show main list items
      if items_count > 0
        message_content += "\n\nMain list items:\n"
        if creation_data[:items].present?
          creation_data[:items].each do |item|
            message_content += "- #{item}\n"
          end
        end
      end

      # Show nested sub-lists structure
      if sublists_count > 0
        message_content += "\n\nCreated sub-lists:\n"
        if creation_data[:sublists].present?
          creation_data[:sublists].each do |sublist|
            message_content += "📋 #{sublist.title}\n"
            if sublist.list_items.present?
              sublist.list_items.each do |item|
                message_content += "  • #{item.title}\n"
              end
            end
          end
        end
      end

      assistant_message = Message.create_assistant(
        chat: @chat,
        content: message_content
      )

      # Trigger refinement to ask clarifying questions
      refinement_result = trigger_list_refinement(
        list: list,
        list_title: parameters["title"],
        category: parameters["category"] || "personal",
        items: creation_data[:items] || [],
        nested_sublists: creation_data[:sublists] || [],
        message: assistant_message
      )

      # If refinement is needed, return the refinement message
      if refinement_result.success? && refinement_result.data[:needs_refinement]
        return success(data: refinement_result.data[:message])
      end
    end

    @chat.update(last_message_at: Time.current)

    success(data: assistant_message)
  end

  # Trigger list refinement and ask clarifying questions
  def trigger_list_refinement(list:, list_title:, category:, items:, message:, nested_sublists: [])
    refinement = ListRefinementService.new(
      list_title: list_title,
      category: category,
      items: items,
      nested_sublists: nested_sublists,
      context: @context
    )

    result = refinement.call

    if result.success? && result.data[:needs_refinement]
      questions = result.data[:questions] || []

      if questions.present?
        # Store refinement state in chat metadata
        @chat.metadata ||= {}
        @chat.metadata["pending_list_refinement"] = {
          list_id: list.id,
          context: result.data[:refinement_context],
          questions_asked: questions.map { |q| q["question"] },
          example_format: "duration, budget, preferences, etc."
        }
        @chat.save

        # Build refinement message
        refinement_message = message.content + "\n\n"
        refinement_message += "I have a few quick questions to make this list even more useful:\n\n"
        questions.each_with_index do |q, idx|
          refinement_message += "#{idx + 1}. #{q["question"]}\n"
        end

        # Create refinement message
        refinement_assistant_message = Message.create_assistant(
          chat: @chat,
          content: refinement_message
        )

        @chat.update(last_message_at: Time.current)

        return success(data: {
          needs_refinement: true,
          message: refinement_assistant_message,
          questions: questions
        })
      end
    end

    success(data: {
      needs_refinement: false,
      message: message
    })
  rescue => e
    Rails.logger.error("List refinement trigger failed: #{e.message}")
    # Graceful fallback - continue without refinement
    success(data: {
      needs_refinement: false,
      message: message
    })
  end

  # Build a user-friendly message asking for missing parameters
  def build_missing_parameter_message(resource_type, missing_params, extracted_params)
    # Only show parameters that have non-empty values
    present_params = extracted_params.select { |_k, v| v.present? && !v.is_a?(Array) }
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
    messages = recent_messages.select { |msg| msg.content.present? && [ "user", "assistant" ].include?(msg.role) }.map do |msg|
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

    # Add tool instructions and plan generation guidelines
    tool_instructions = <<~PROMPT
      You can help users by:
      1. Answering questions about their data
      2. Navigating them to specific pages (when they ask to "show all users", "list organizations", etc.)
      3. Creating new resources (users, teams, lists) when requested
      4. Updating existing resources (changing roles, statuses, etc.)
      5. Searching for information across the app

      When a user asks to view something like "show me active users" or "list all organizations",
      recognize their intent and help them navigate to the appropriate page or retrieve the information.

      CREATING STRUCTURED PLANS - CRITICAL INSTRUCTION:
      =================================================
      WHEN USER ASKS FOR A PLAN, LEARNING PATH, ITINERARY, ROADMAP, OR STRUCTURED APPROACH:
      YOU MUST call create_list with nested_lists parameter (NOT just items).

      DO NOT create flat lists. Create 3-5 SUB-LISTS with 4-7 ITEMS EACH.

      EXACT JSON STRUCTURE to use in create_list tool call:
      {
        "title": "Social Marketing Development Plan",
        "items": [],
        "nested_lists": [
          {
            "title": "Month 1: Foundations",
            "description": "Build fundamental social media knowledge and establish foundational skills",
            "items": [
              {
                "title": "Learn social media platform basics",
                "description": "Understand core features of Twitter, LinkedIn, Instagram, and TikTok"
              },
              {
                "title": "Study audience psychology and targeting",
                "description": "Learn how to identify and effectively reach your target audience"
              },
              {
                "title": "Read 'Book 1: Social Media Marketing Basics'",
                "description": "Complete foundational book on social media fundamentals"
              },
              {
                "title": "Set up analytics dashboard",
                "description": "Create comprehensive tracking system for social media metrics"
              },
              {
                "title": "Create personal brand statement",
                "description": "Define your unique value proposition and brand positioning"
              }
            ]
          },
          {
            "title": "Month 2: Strategy & Analytics",
            "description": "Master analytics tools and develop data-driven marketing strategies",
            "items": [
              {
                "title": "Learn analytics tools and metrics",
                "description": "Master Google Analytics and platform-specific analytics dashboards"
              },
              {
                "title": "Study competitor analysis techniques",
                "description": "Learn how to analyze competitor strategies and performance"
              },
              {
                "title": "Read 'Book 2: Data-Driven Social Marketing'",
                "description": "Deep dive into analytics and data-driven decision making"
              },
              {
                "title": "Create content calendar template",
                "description": "Design your posting schedule and content planning system"
              },
              {
                "title": "Analyze 3 competitor accounts",
                "description": "Conduct detailed analysis of successful accounts in your niche"
              }
            ]
          }
        ]
      }

      CRITICAL RULES FOR PLAN GENERATION:
      1. Always use nested_lists parameter for creating plans (not just items)
      2. Create 3-5 sub-lists representing phases, months, categories, or topics
      3. Each sub-list MUST have a title and description
      4. Each sub-list MUST have 4-7 items
      5. Each item MUST have a title and description (2-3 sentences)
      6. Structure should naturally flow (chronological, topical, or logical progression)
      7. Include diverse elements (learning, reading, practice, projects, reflection)
      8. Make items concrete and measurable
      9. Tailor structure to user's context (duration, budget, preferences, background)
    PROMPT

    "#{base_prompt}\n\n#{tool_instructions}"
  end
end
