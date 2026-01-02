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
      # Check if we're in pre-creation planning state FIRST
      # This takes precedence over other pending flows
      if pending_pre_creation_planning?
        planning_result = handle_pre_creation_planning_response
        return planning_result if planning_result
      end

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

  # Detect if a list creation request requires pre-creation planning
  # Returns true for complex, multi-step requests that benefit from upfront context
  def needs_pre_creation_planning?(parameters)
    title = parameters["title"] || parameters[:title] || ""
    items = parameters["items"] || parameters[:items] || []
    nested_lists = parameters["nested_lists"] || parameters[:nested_lists] || []

    # HEURISTIC 1: Nested structure already detected by parameter extraction
    return true if nested_lists.present? && nested_lists.length > 2

    # HEURISTIC 2: Multi-location patterns
    # Keywords: roadshow, tour, trip, visit, cities, countries
    multi_location_keywords = ["roadshow", "tour", "trip", "visit", "cities", "countries", "locations"]
    has_location_pattern = multi_location_keywords.any? { |kw| title.downcase.include?(kw) }

    # HEURISTIC 3: Time-bound programs
    # Keywords: week, month, day, plan, program, schedule, phase
    # Pattern: "X weeks", "X months", "8-week", etc.
    time_bound_keywords = ["week", "month", "day", "program", "schedule", "phase"]
    has_time_pattern = time_bound_keywords.any? { |kw| title.downcase.include?(kw) } ||
                       title.match?(/\d+[\s-]+(week|month|day|phase)/i)

    # HEURISTIC 4: Hierarchical/staged keywords
    hierarchy_keywords = ["stages", "phases", "modules", "milestones", "steps"]
    has_hierarchy = hierarchy_keywords.any? { |kw| title.downcase.include?(kw) }

    # HEURISTIC 5: Large item count (suggests complexity)
    has_many_items = items.length > 8

    # Return true if ANY complexity indicator is found
    has_location_pattern || has_time_pattern || has_hierarchy || has_many_items
  end

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
    # For list creation, check if we need pre-creation planning
    if intent == "create_list"
      parameters = data[:parameters] || {}

      # Check if this is a complex request requiring pre-creation planning
      if needs_pre_creation_planning?(parameters)
        Rails.logger.info("ChatCompletionService - Detected complex list request, routing to pre-creation planning")
        return handle_pre_creation_planning(parameters)
      else
        Rails.logger.info("ChatCompletionService#check_parameters_for_intent - Proceeding with list creation, parameters: #{parameters.inspect}")
        return handle_list_creation("list", parameters)
      end
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

  # Handle pre-creation planning for complex list requests
  # Ask clarifying questions BEFORE creating the list
  def handle_pre_creation_planning(parameters)
    title = parameters["title"] || "your list"
    category = parameters["category"] || "personal"
    items = parameters["items"] || []
    nested_lists = parameters["nested_lists"] || []

    # REUSE ListRefinementService to generate questions
    refinement = ListRefinementService.new(
      list_title: title,
      category: category,
      items: items,
      nested_sublists: nested_lists,
      context: @context
    )

    result = refinement.call

    if result.success? && result.data[:needs_refinement]
      questions = result.data[:questions] || []

      if questions.present?
        # Store pre-creation planning state in chat metadata
        @chat.metadata ||= {}
        @chat.metadata["pending_pre_creation_planning"] = {
          extracted_params: parameters,
          questions_asked: questions.map { |q| q["question"] },
          refinement_context: result.data[:refinement_context],
          intent: "create_list"
        }
        @chat.save

        # Build planning message
        planning_message = "Before I create \"#{title}\", I have a few questions to help me structure it better:\n\n"
        questions.each_with_index do |q, idx|
          planning_message += "#{idx + 1}. #{q["question"]}\n"
        end

        assistant_message = Message.create_assistant(
          chat: @chat,
          content: planning_message
        )

        @chat.update(last_message_at: Time.current)

        return success(data: assistant_message)
      end
    end

    # Fallback: if refinement fails or no questions, proceed with creation
    Rails.logger.warn("Pre-creation planning failed to generate questions, falling back to immediate creation")
    handle_list_creation("list", parameters)
  rescue => e
    Rails.logger.error("Pre-creation planning failed: #{e.message}")
    # Graceful degradation: proceed with immediate creation
    handle_list_creation("list", parameters)
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

  # Check if we're in a pre-creation planning state
  def pending_pre_creation_planning?
    @chat.metadata&.dig("pending_pre_creation_planning").present?
  end

  # Check if we're in a list refinement state
  def pending_list_refinement?
    @chat.metadata&.dig("pending_list_refinement").present?
  end

  # Handle user's response to pre-creation planning questions
  def handle_pre_creation_planning_response
    planning_data = @chat.metadata["pending_pre_creation_planning"]
    return nil unless planning_data

    extracted_params = planning_data["extracted_params"] || {}

    # Extract planning parameters from user's answers
    planning_params = extract_planning_parameters_from_answers(
      user_answers: @user_message.content,
      list_title: extracted_params["title"],
      category: extracted_params["category"],
      initial_items: extracted_params["items"] || []
    )

    # Enrich the list structure with planning context
    enriched_params = enrich_list_structure_with_planning(
      base_params: extracted_params,
      planning_params: planning_params
    )

    # Clear pre-creation planning state
    @chat.metadata.delete("pending_pre_creation_planning")

    # Mark that we should skip post-creation refinement
    @chat.metadata["skip_post_creation_refinement"] = true
    @chat.save

    # Create the list with enriched structure
    creation_result = handle_list_creation("list", enriched_params)

    # Clear the skip flag after creation
    @chat.metadata.delete("skip_post_creation_refinement")
    @chat.save

    creation_result
  rescue => e
    Rails.logger.error("Pre-creation planning response handling failed: #{e.message}")

    # Fallback: create list with original params
    @chat.metadata.delete("pending_pre_creation_planning")
    @chat.save

    handle_list_creation("list", extracted_params)
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
    # Skip post-creation refinement if we already did pre-creation planning
    if @chat.metadata&.dig("skip_post_creation_refinement")
      Rails.logger.info("Skipping post-creation refinement (pre-creation planning was completed)")
      return success(data: { needs_refinement: false, message: message })
    end

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

  # Extract planning parameters from user's answers to planning questions
  def extract_planning_parameters_from_answers(user_answers:, list_title:, category:, initial_items:)
    llm_chat = RubyLLM::Chat.new(provider: :openai, model: "gpt-4o-mini")

    system_prompt = <<~PROMPT
      Extract planning parameters from the user's answers.

      List Context:
      - Title: "#{list_title}"
      - Category: #{category}
      - Initial items: #{initial_items.join(", ")}

      Respond with ONLY a JSON object (no other text):
      {
        "duration": "extracted time/duration if mentioned",
        "budget": "extracted budget if mentioned",
        "locations": ["extracted locations if multi-location event"],
        "start_date": "extracted start date if mentioned",
        "timeline": "extracted timeline/deadline if mentioned",
        "team_size": "extracted team/people count if mentioned",
        "phases": ["extracted phases/stages if mentioned"],
        "preferences": "extracted preferences/constraints",
        "other_details": "any other relevant context"
      }

      Rules:
      1. Extract only information actually mentioned
      2. Be specific and preserve units (e.g., "3 days", "$2000")
      3. If locations mentioned, extract as array ["New York", "Chicago"]
      4. If phases/stages mentioned, extract as array ["Phase 1", "Phase 2"]
      5. Return empty string or empty array for fields not mentioned

      User's answers: "#{user_answers}"
    PROMPT

    llm_chat.add_message(role: "system", content: system_prompt)
    llm_chat.add_message(role: "user", content: "Extract planning parameters from these answers.")

    response = llm_chat.complete
    response_text = extract_response_content(response)

    json_match = response_text.match(/\{[\s\S]*\}/m)
    return {} unless json_match

    begin
      JSON.parse(json_match[0])
    rescue JSON::ParserError
      {}
    end
  rescue => e
    Rails.logger.error("Planning parameter extraction failed: #{e.message}")
    {}
  end

  # Enrich list structure based on planning parameters
  def enrich_list_structure_with_planning(base_params:, planning_params:)
    enriched = base_params.dup

    # Update description with planning context
    description_parts = [enriched["description"]].compact

    if planning_params["duration"].present?
      description_parts << "Duration: #{planning_params["duration"]}"
    end

    if planning_params["budget"].present?
      description_parts << "Budget: #{planning_params["budget"]}"
    end

    if planning_params["start_date"].present?
      description_parts << "Start: #{planning_params["start_date"]}"
    end

    enriched["description"] = description_parts.join(" | ") if description_parts.present?

    # If locations were mentioned, create nested lists for each location
    if planning_params["locations"].present? && planning_params["locations"].is_a?(Array)
      enriched["nested_lists"] = planning_params["locations"].map do |location|
        {
          "title" => location,
          "description" => "Tasks and activities for #{location}",
          "items" => (enriched["items"] || []).map do |item|
            if item.is_a?(Hash)
              item.merge("description" => "#{item["title"]} in #{location}")
            else
              { "title" => item, "description" => "In #{location}" }
            end
          end
        }
      end

      # Clear parent items since they're now in nested lists
      enriched["items"] = []
    end

    # If phases were mentioned, create nested lists for each phase
    if planning_params["phases"].present? && planning_params["phases"].is_a?(Array)
      enriched["nested_lists"] = planning_params["phases"].map.with_index do |phase, idx|
        {
          "title" => phase,
          "description" => "Phase #{idx + 1} of #{planning_params["phases"].length}",
          "items" => []
        }
      end
    end

    enriched
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

      CREATING STRUCTURED PLANS - INTELLIGENT INSTRUCTION:
      ====================================================
      WHEN USER ASKS FOR A PLAN, LEARNING PATH, ITINERARY, ROADMAP, OR STRUCTURED APPROACH:
      YOU MUST call create_list with nested_lists parameter (NOT just items).

      YOU ARE INTELLIGENT. Do NOT follow arbitrary rules or numbers.
      Instead, think deeply about what structure makes sense for THIS user's SPECIFIC request.

      Ask yourself:
      - What is the natural structure? (time-based, topic-based, location-based, phase-based?)
      - How many meaningful divisions exist? (Not "3-5" but what actually makes sense)
      - How many actionable items per section? (Varies by complexity and importance)
      - What level of detail does this context require?
      - What are the user's constraints? (time, budget, experience, preferences)

      EXAMPLES (NOT rules, just to show the variety of intelligent structures):
      - "Learn piano in 6 months" → Could be 6 monthly phases OR 3 skill-level phases depending on pace
      - "Europe trip with 5 countries" → 5 sub-lists (one per country), not a fixed number
      - "Build a startup" → 5-8 phases (MVP, Launch, Growth, Scale) based on complexity
      - "2-year MBA plan" → 8 quarters or 4 semesters or however makes pedagogical sense
      - "Wedding planning" → Phases based on timeline (3 months out = fewer sub-lists, 1 year = more detail)

      The number of items per section depends entirely on that section's complexity:
      - A simple onboarding phase might have 2-3 items
      - A complex feature development phase might have 8-10 items
      - Never force padding or arbitrarily limit items

      EXACT JSON FORMAT (example for 4-month plan - but your structure should be context-appropriate):
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
              }
            ]
          }
        ]
      }

      CRITICAL PRINCIPLES (NOT rules):
      1. Always use nested_lists for plans - DO NOT create flat lists
      2. Choose the NATURAL structure for this specific context (not a template)
      3. Each sub-list MUST have:
         - A clear, descriptive title (explains what this section is about)
         - A description (what the user will accomplish in this section)
         - Items appropriate to that section's scope (no artificial minimums or maximums)
      4. Each item MUST have:
         - A clear, actionable title
         - A description that adds context, not just reiterates the title
      5. Structure flows logically (chronological, skill progression, logical dependencies, etc.)
      6. Include diverse elements (learning, practice, reflection, output, feedback)
      7. All items are concrete and measurable (not vague)
      8. The ENTIRE structure is tailored to:
         - User's experience level
         - Available time and budget
         - Stated preferences and constraints
         - The specific goal and context they provided
    PROMPT

    "#{base_prompt}\n\n#{tool_instructions}"
  end
end
