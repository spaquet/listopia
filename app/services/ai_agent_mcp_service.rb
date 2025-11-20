# app/services/ai_agent_mcp_service.rb
class AiAgentMcpService
  attr_reader :user, :context, :chat, :current_message, :extracted_data

  def initialize(user:, context: {})
    @user = user
    @context = context
    @chat = find_or_create_chat
    @extracted_data = {}
    @user_tools = McpTools::UserManagementTools.new(user, context)
    @collaboration_tools = McpTools::CollaborationTools.new(user, context)
  end

  def process_message(message_content)
    @current_message = message_content
    log_debug "=" * 80
    log_debug "NEW MESSAGE: #{message_content}"
    log_debug "=" * 80

    # SAVE USER MESSAGE to database
    @chat.messages.create!(
      role: "user",
      content: message_content,
      user: @user
    )

    # STEP 1: Content moderation
    moderation_result = moderate_content(message_content)
    if moderation_result[:blocked]
      log_debug "MODERATION: Content blocked - #{moderation_result[:categories].join(', ')}"

      assistant_message = @chat.messages.create!(
        role: "assistant",
        content: moderation_result[:message],
        user: nil
      )

      return {
        message: assistant_message,
        lists_created: [],
        items_created: [],
        message_type: "error"  # NEW: specify message type
      }
    end
    log_debug "MODERATION: Content passed"

    # Execute multi-step AI workflow
    result = execute_multi_step_workflow

    # Build assistant response text
    assistant_text = build_assistant_response(result)

    # SAVE ASSISTANT MESSAGE to database
    assistant_message = @chat.messages.create!(
      role: "assistant",
      content: assistant_text,
      user: nil
    )

    # NEW: Determine message type based on results
    message_type = if result[:lists_created].any? || result[:items_created].any?
      "success"
    else
      "regular"
    end

    {
      message: assistant_message,
      lists_created: result[:lists_created],
      items_created: result[:items_created],
      message_type: message_type  # NEW: include message type
    }

  rescue => e
    Rails.logger.error "AI Agent error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")

    error_text = "I encountered an error processing your request. Please try again."

    error_message = @chat.messages.create!(
      role: "assistant",
      content: error_text,
      user: nil
    )

    {
      message: error_message,
      lists_created: [],
      items_created: [],
      error: e.message,
      message_type: "error"  # NEW: specify error type
    }
  end

  private

  def create_user_from_analysis(params)
    # Validate permissions
    unless @user.admin?
      return {
        success: false,
        error: "Only administrators can create users.",
        unauthorized: true
      }
    end

    # Validate required parameters
    unless params["email"].present?
      return {
        success: false,
        error: "Email is required to create a user.",
        errors: [ "Email cannot be blank" ]
      }
    end

    # Check if user already exists
    if User.exists?(email: params["email"])
      return {
        success: false,
        error: "User with this email already exists.",
        errors: [ "Email has already been taken" ]
      }
    end

    begin
      # Create the user WITHOUT generating password
      new_user = User.new(
        name: params["name"] || params["email"].split("@").first.capitalize,
        email: params["email"],
        bio: params["bio"],
        locale: params["locale"] || "en",
        timezone: params["timezone"] || "UTC",
        admin_notes: params["admin_notes"]
      )

      # Mark email as verified for admin-created users
      new_user.email_verified_at = Time.current

      if new_user.save
        # Add admin role if requested
        new_user.add_role(:admin) if params["make_admin"] == true

        log_debug "✓ User created: #{new_user.email}"

        {
          success: true,
          message: "User #{new_user.email} created successfully.",
          user: {
            id: new_user.id,
            name: new_user.name,
            email: new_user.email,
            status: new_user.status,
            admin: new_user.admin?,
            sign_in_count: new_user.sign_in_count,
            last_sign_in_at: new_user.last_sign_in_at
          }
        }
      else
        log_error "Failed to create user: #{new_user.errors.full_messages.join(', ')}"

        {
          success: false,
          error: "Failed to create user.",
          errors: new_user.errors.full_messages
        }
      end
    rescue => e
      log_error "Error in create_user_from_analysis: #{e.message}", e

      {
        success: false,
        error: "An unexpected error occurred while creating the user.",
        errors: [ e.message ]
      }
    end
  end

  def success_response(data = {})
    {
      success: true,
      message: data[:message] || "Action completed successfully.",
      user: data[:user],
      users: data[:users],
      count: data[:count],
      total_count: data[:total_count],
      statistics: data[:statistics]
    }
  end

  def error_response(errors = [])
    {
      success: false,
      error: "An error occurred.",
      errors: Array(errors),
      unauthorized: false
    }
  end

  def find_or_create_chat
    existing = @user.chats.where(status: "active")
                         .order(last_message_at: :desc, created_at: :desc)
                         .first
    return existing if existing

    @user.chats.create!(
      title: "AI Chat - #{Time.current.strftime('%m/%d %H:%M')}",
      status: "active",
      conversation_state: "stable"
    )
  end

  def moderate_content(content)
    return { blocked: false } unless moderation_enabled?

    begin
      log_debug "STEP 1: Running content moderation..."
      moderation_result = RubyLLM.moderate(content)

      if moderation_result.flagged?
        flagged_categories = moderation_result.categories
        log_debug "MODERATION FLAGGED: #{flagged_categories.join(', ')}"

        {
          blocked: true,
          categories: flagged_categories,
          message: generate_moderation_message(flagged_categories)
        }
      else
        log_debug "MODERATION PASSED: Content is safe"
        { blocked: false }
      end
    rescue => e
      Rails.logger.error "Moderation API failed: #{e.message}"
      { blocked: false }
    end
  end

  def moderation_enabled?
    ENV.fetch("LISTOPIA_USE_MODERATION", "true").downcase == "true"
  end

  def generate_moderation_message(flagged_categories)
    case
    when flagged_categories.include?("hate") || flagged_categories.include?("hate/threatening")
      "I can't create lists with hateful content. Please rephrase your request without targeting any groups or individuals."
    when flagged_categories.include?("violence") || flagged_categories.include?("violence/graphic")
      "I can't create lists involving violent content. Let me help you organize something constructive instead."
    when flagged_categories.include?("self-harm")
      "I'm concerned about your request. If you're going through a difficult time, please reach out to a mental health professional. I'm here to help with positive planning."
    when flagged_categories.include?("sexual")
      "I can't create lists with sexual content. Let me help you organize something else."
    else
      "Your request doesn't align with our content guidelines. I'm here to help you create productive lists."
    end
  end

  def handle_blocked_content(moderation_result)
    {
      message: moderation_result[:message],
      lists_created: [],
      items_created: [],
      moderation_blocked: true,
      flagged_categories: moderation_result[:categories]
    }
  end

  def execute_multi_step_workflow
    log_debug "\n" + "=" * 80
    log_debug "STARTING MULTI-STEP AI WORKFLOW"
    log_debug "=" * 80

    # STEP 1: Detect the intent of the user's message
    intent_analysis = detect_user_intent
    return handle_workflow_failure("intent detection") if intent_analysis.nil?

    log_debug "INTENT DETECTED: #{intent_analysis["intent"]}"

    # STEP 2: Route based on detected intent
    case intent_analysis["intent"]
    when "user_management"
      return handle_user_management_request
    when "collaboration"
      return handle_collaboration_request
    when "list_creation"
      # Continue to list creation workflow
    else
      # Default to list creation workflow
    end

    # STEP 3: Categorize and extract everything in ONE call
    analysis = analyze_and_extract_request
    return handle_workflow_failure("analysis") if analysis.nil?

    log_debug "ANALYSIS RESULT: #{analysis.inspect}"

    # STEP 3: Execute the plan
    execution_result = execute_creation_plan(analysis)

    log_debug "EXECUTION RESULT: Created #{execution_result[:lists_created].count} lists, #{execution_result[:items_created].count} items"
    log_debug "=" * 80 + "\n"

    execution_result

  rescue => e
    log_error "Workflow failed: #{e.message}", e
    handle_workflow_failure("workflow execution")
  end

  def build_assistant_response(result)
    lists_count = result[:lists_created]&.count || 0
    items_count = result[:items_created]&.count || 0

    if result[:user_management_result]
      return build_user_management_response(result[:user_management_result])
    end

    if result[:collaboration_result]
      return build_collaboration_response(result[:collaboration_result])
    end

    if lists_count == 1 && items_count > 0
      "Created '#{result[:lists_created].first.title}' with #{items_count} items."
    elsif lists_count > 1
      "Created #{lists_count} lists with #{items_count} total items."
    elsif lists_count == 1
      "Created '#{result[:lists_created].first.title}'."
    else
      "Task completed successfully."
    end
  end

  # Single AI call that does everything: categorize, determine structure, extract items
  def analyze_and_extract_request
    log_debug "\n--- COMPREHENSIVE ANALYSIS ---"

    prompt = <<~PROMPT
      Analyze this user request and create a complete execution plan. This is an AI-driven task management system like Asana or Monday.com.

      User Request: "#{@current_message}"

      Analyze and determine:
      1. List type (professional or personal)
      2. Appropriate title
      3. Structure needed (simple flat list OR hierarchical with sublists)
      4. Extract ALL items with proper quantities

      CRITICAL RULES FOR ITEM EXTRACTION:
      - Each comma-separated item = ONE separate entry
      - "2 apples, milk, chocolate, 1 bottle" = 4 items total
      - If user says "5 books", generate 5 SPECIFIC book titles
      - If user says "10 tasks", generate 10 SPECIFIC tasks
      - Include quantities in titles ("2 apples", "1 bottle of water")
      - NEVER combine items, NEVER truncate
      - Count carefully: "item1, item2, and item3" = 3 items

      STRUCTURE RULES:
      - Simple requests = flat list (e.g., "grocery list with apples, milk")
      - Multi-location/phase requests = hierarchical (e.g., "roadshow in NYC, SF, Austin")
      - Generate appropriate sublists automatically when needed

      Respond with ONLY valid JSON (no markdown, no code blocks):
      {
        "list_type": "professional|personal",
        "title": "Clear, descriptive title",
        "domain": "Brief description",
        "structure": "simple|hierarchical",
        "main_items": [
          {"title": "Item with quantity", "description": "", "priority": "medium"}
        ],
        "sublists": [
          {
            "title": "Sublist name (e.g., NYC Event)",
            "items": [
              {"title": "Specific item", "description": "", "priority": "medium"}
            ]
          }
        ],
        "total_items": 0,
        "total_sublists": 0
      }

      EXAMPLES:

      Request: "grocery list with 2 apples, milk, chocolate and 1 bottle of water"
      {
        "list_type": "personal",
        "title": "Grocery Shopping",
        "domain": "food and household items",
        "structure": "simple",
        "main_items": [
          {"title": "2 apples", "description": "", "priority": "medium"},
          {"title": "Milk", "description": "", "priority": "medium"},
          {"title": "Chocolate", "description": "", "priority": "medium"},
          {"title": "1 bottle of water", "description": "", "priority": "medium"}
        ],
        "sublists": [],
        "total_items": 4,
        "total_sublists": 0
      }

      Request: "roadshow planning for NYC, San Francisco, and Austin"
      {
        "list_type": "professional",
        "title": "Roadshow Planning",
        "domain": "multi-city business events",
        "structure": "hierarchical",
        "main_items": [
          {"title": "Create master timeline", "description": "", "priority": "high"},
          {"title": "Book travel arrangements", "description": "", "priority": "high"}
        ],
        "sublists": [
          {
            "title": "NYC Event",
            "items": [
              {"title": "Book venue in NYC", "description": "", "priority": "high"},
              {"title": "Coordinate NYC catering", "description": "", "priority": "medium"},
              {"title": "Send NYC invitations", "description": "", "priority": "medium"}
            ]
          },
          {
            "title": "San Francisco Event",
            "items": [
              {"title": "Book venue in San Francisco", "description": "", "priority": "high"},
              {"title": "Coordinate SF catering", "description": "", "priority": "medium"},
              {"title": "Send SF invitations", "description": "", "priority": "medium"}
            ]
          },
          {
            "title": "Austin Event",
            "items": [
              {"title": "Book venue in Austin", "description": "", "priority": "high"},
              {"title": "Coordinate Austin catering", "description": "", "priority": "medium"},
              {"title": "Send Austin invitations", "description": "", "priority": "medium"}
            ]
          }
        ],
        "total_items": 11,
        "total_sublists": 3
      }

      Be creative and specific. Generate appropriate items for any domain.
    PROMPT

    response = call_ai_with_json_mode(prompt)
    return nil unless response

    result = parse_json_response(response, "comprehensive analysis")

    if result
      log_debug "List type: #{result['list_type']}"
      log_debug "Title: #{result['title']}"
      log_debug "Structure: #{result['structure']}"
      log_debug "Total items: #{result['total_items']}"
      log_debug "Total sublists: #{result['total_sublists']}"
    end

    result
  end

  # Make AI call that FORCES JSON output without tool calls
  def call_ai_with_json_mode(prompt, max_retries: 3)
    retry_count = 0

    begin
      log_debug "Calling AI (attempt #{retry_count + 1}/#{max_retries})..."

      # Get the configured model from your project
      model = Model.find_or_create_by(
        provider: ENV.fetch("LLM_PROVIDER", "openai"),
        name: ENV.fetch("LLM_MODEL", "gpt-4o-mini")
      )

      model_name = model.name

      chat = RubyLLM.chat(model: model_name)

      system_content = "You are a JSON-only assistant. Respond ONLY with valid JSON. No tool calls, no markdown, no explanation. Just pure JSON."

      chat.add_message(role: :system, content: system_content)

      response = chat.ask(prompt)

      log_debug "AI response received (#{response.content.length} chars)"
      response.content

    rescue => e
      retry_count += 1
      log_error "AI call attempt #{retry_count} failed: #{e.message}"

      if retry_count < max_retries
        sleep(retry_count * 2)
        retry
      else
        log_error "All AI call attempts failed"
        nil
      end
    end
  end

  def parse_json_response(response_text, step_name)
    # Remove markdown code blocks
    cleaned = response_text.gsub(/```json\n?/, "").gsub(/```\n?/, "").strip

    # Find the JSON object
    start_idx = cleaned.index("{")
    return nil unless start_idx

    brace_count = 0
    in_string = false
    escape_next = false
    end_idx = nil

    (start_idx...cleaned.length).each do |i|
      char = cleaned[i]

      if escape_next
        escape_next = false
        next
      end

      escape_next = true if char == "\\"
      next if escape_next

      if char == '"'
        in_string = !in_string
        next
      end

      next if in_string

      brace_count += 1 if char == "{"
      brace_count -= 1 if char == "}"

      if brace_count == 0
        end_idx = i
        break
      end
    end

    return nil unless end_idx

    JSON.parse(cleaned[start_idx..end_idx])
  rescue JSON::ParserError => e
    log_error "JSON parsing failed for #{step_name}: #{e.message}"
    log_error "Response preview: #{response_text.truncate(300)}"
    nil
  end

  def execute_creation_plan(analysis)
    log_debug "\n--- EXECUTION ---"

    if analysis["structure"] == "hierarchical" && analysis["sublists"]&.any?
      create_hierarchical_lists(analysis)
    else
      create_simple_list(analysis)
    end
  end

  def create_simple_list(analysis)
    log_debug "Creating SIMPLE list..."

    lists_created = []
    items_created = []

    list = @user.lists.create!(
      title: analysis["title"] || "New List",
      description: analysis["domain"] || "Created via AI",
      status: "active",
      list_type: analysis["list_type"] || "personal",
      organization_id: @context[:organization_id]
    )
    lists_created << list
    log_debug "Created list: #{list.title}"

    items = analysis["main_items"] || []
    items.each_with_index do |item_data, index|
      item = list.list_items.create!(
        title: item_data["title"],
        description: item_data["description"],
        status: :pending,
        priority: item_data["priority"] || "medium",
        item_type: "task",
        position: index
      )
      items_created << item
      log_debug "  ✓ #{item.title}"
    end

    {
      success: true,
      message: "Created '#{list.title}' with #{items_created.count} items.",
      lists_created: lists_created,
      items_created: items_created
    }
  end

  def create_hierarchical_lists(analysis)
    log_debug "Creating HIERARCHICAL structure..."

    lists_created = []
    items_created = []

    main_list = @user.lists.create!(
      title: analysis["title"] || "Project",
      description: analysis["domain"] || "Created via AI",
      status: "active",
      list_type: analysis["list_type"] || "professional",
      organization_id: @context[:organization_id]
    )
    lists_created << main_list
    log_debug "Created main list: #{main_list.title}"

    # Main items
    (analysis["main_items"] || []).each_with_index do |item_data, index|
      item = main_list.list_items.create!(
        title: item_data["title"],
        description: item_data["description"],
        status: :pending,
        priority: item_data["priority"] || "medium",
        item_type: "task",
        position: index
      )
      items_created << item
      log_debug "  ✓ #{item.title}"
    end

    # Sublists
    (analysis["sublists"] || []).each do |sublist_data|
      sublist = @user.lists.create!(
        title: sublist_data["title"],
        parent_list: main_list,
        status: "active",
        list_type: analysis["list_type"] || "professional",
        organization_id: @context[:organization_id]
      )
      lists_created << sublist
      log_debug "  Created sublist: #{sublist.title}"

      (sublist_data["items"] || []).each_with_index do |item_data, idx|
        item = sublist.list_items.create!(
          title: item_data["title"],
          description: item_data["description"],
          status: :pending,
          priority: item_data["priority"] || "medium",
          item_type: "task",
          position: idx
        )
        items_created << item
        log_debug "    ✓ #{item.title}"
      end
    end

    {
      success: true,
      message: "Created '#{main_list.title}' with #{analysis['total_sublists']} sublists and #{items_created.count} items.",
      lists_created: lists_created,
      items_created: items_created
    }
  end

  def handle_workflow_failure(failed_step)
    log_error "Workflow failed at: #{failed_step}"

    list = @user.lists.create!(
      title: "New List",
      description: "Created via AI - please add items manually",
      status: "active",
      list_type: "personal",
      organization_id: @context[:organization_id]
    )

    {
      success: false,
      message: "I created a list for you, but couldn't extract all items. Please add items manually.",
      lists_created: [ list ],
      items_created: []
    }
  end

  # ============================================================================
  # INTENT DETECTION - Use AI to understand user's intent
  # ============================================================================

  def detect_user_intent
    prompt = <<~PROMPT
      Analyze the user's message and determine their primary intent.

      User message: "#{@current_message}"

      Respond with JSON containing:
      {
        "intent": "user_management|collaboration|list_creation",
        "confidence": 0.0-1.0,
        "reasoning": "brief explanation of why this intent was detected"
      }

      Intent definitions:
      - "user_management": The user wants to manage users (create, suspend, deactivate, grant admin, etc.)
        Examples: "create a new user", "suspend john@example.com", "list all users", "make jane an admin"

      - "collaboration": The user wants to share lists/items or manage collaborators
        Examples: "invite alice@example.com to my grocery list", "share this project with bob", "who has access to my todo list", "remove dave from the list"

      - "list_creation": The user wants to create a new list or manage list items
        Examples: "create a grocery list with milk, bread, eggs", "add a new task to my project", "I need a todo list for my home renovation"

      Return ONLY valid JSON, no additional text.
    PROMPT

    response = call_ai_with_json_mode(prompt)
    return nil unless response

    parse_json_response(response, "intent detection")
  end

  # Handle user management requests
  def handle_user_management_request
    log_debug "Detected user management request"

    # Analyze the request to determine action and parameters
    analysis = analyze_user_management_request
    return handle_workflow_failure("user management analysis") if analysis.nil?

    # Execute the appropriate user management action
    result = execute_user_management_action(analysis)

    {
      lists_created: [],
      items_created: [],
      user_management_result: result,
      analysis: analysis
    }
  end

  # Analyze what user management action is requested
  def analyze_user_management_request
    prompt = <<~PROMPT
      Analyze this user management request and extract the action and parameters.

      User message: "#{@current_message}"

      Respond with JSON containing:
      {
        "action": "list_users|get_user|create_user|update_user|delete_user|suspend_user|unsuspend_user|deactivate_user|reactivate_user|grant_admin|revoke_admin|update_notes|get_statistics",
        "parameters": {
          "user_id": "optional UUID",
          "name": "optional string",
          "email": "optional string",
          "password": "optional string",
          "reason": "optional string for suspend/deactivate",
          "notes": "optional string for admin notes",
          "filters": {
            "status": "optional: active|suspended|deactivated",
            "email": "optional email search",
            "name": "optional name search",
            "admin": true/false
          }
        },
        "requires_confirmation": true/false
      }

      Examples:
      - "list all users" -> {"action": "list_users", "parameters": {}}
      - "show me suspended users" -> {"action": "list_users", "parameters": {"filters": {"status": "suspended"}}}
      - "suspend user john@example.com for violating terms" -> {"action": "suspend_user", "parameters": {"email": "john@example.com", "reason": "violating terms"}}
      - "make user jane@example.com an admin" -> {"action": "grant_admin", "parameters": {"email": "jane@example.com"}}
      - "update my email to newemail@example.com" -> {"action": "update_user", "parameters": {"email": "newemail@example.com"}}
    PROMPT

    response = call_ai_with_json_mode(prompt)
    return nil unless response

    parse_json_response(response, "user management analysis")
  end

  # Execute the user management action
  def execute_user_management_action(analysis)
    action = analysis["action"]
    params = analysis["parameters"] || {}

    # Convert string keys to symbols immediately
    params = params.transform_keys(&:to_sym)

    # Find user by email if email provided instead of ID
    if params[:email].present? && params[:user_id].nil?
      target_user = User.find_by(email: params[:email])
      params[:user_id] = target_user&.id
    end

    log_debug "Executing user management action: #{action}"

    case action
    when "list_users"
      @user_tools.list_users(filters: params[:filters] || {})
    when "get_user"
      @user_tools.get_user(user_id: params[:user_id])
    when "create_user"
      create_user_from_analysis(params)
    when "update_user"
      # If no user_id, assume updating current user
      params[:user_id] ||= @user.id
      @user_tools.update_user(**params)
    when "delete_user"
      @user_tools.delete_user(user_id: params[:user_id])
    when "suspend_user"
      @user_tools.suspend_user(user_id: params[:user_id], reason: params[:reason])
    when "unsuspend_user"
      @user_tools.unsuspend_user(user_id: params[:user_id])
    when "deactivate_user"
      @user_tools.deactivate_user(user_id: params[:user_id], reason: params[:reason])
    when "reactivate_user"
      @user_tools.reactivate_user(user_id: params[:user_id])
    when "grant_admin"
      @user_tools.grant_admin(user_id: params[:user_id])
    when "revoke_admin"
      @user_tools.revoke_admin(user_id: params[:user_id])
    when "update_notes"
      @user_tools.update_user_notes(user_id: params[:user_id], notes: params[:notes])
    when "get_statistics"
      @user_tools.get_user_statistics
    else
      {
        success: false,
        error: "Unknown user management action: #{action}"
      }
    end
  rescue => e
    log_error "Error executing user management action: #{e.message}"
    {
      success: false,
      error: "Failed to execute user management action: #{e.message}"
    }
  end

  # ============================================================================
  # COLLABORATION MANAGEMENT
  # ============================================================================

  # Handle collaboration requests
  def handle_collaboration_request
    log_debug "Detected collaboration request"

    # Analyze the request to determine action and parameters
    analysis = analyze_collaboration_request
    return handle_workflow_failure("collaboration analysis") if analysis.nil?

    # Execute the appropriate collaboration action
    result = execute_collaboration_action(analysis)

    {
      lists_created: [],
      items_created: [],
      collaboration_result: result,
      analysis: analysis
    }
  end

  # Analyze what collaboration action is requested
  def analyze_collaboration_request
    prompt = <<~PROMPT
      Analyze this collaboration request and extract the action and parameters.

      User message: "#{@current_message}"

      Current user's lists: #{@user.lists.pluck(:id, :title).to_json}

      Respond with JSON containing:
      {
        "action": "invite_collaborator|list_resources_for_disambiguation|list_collaborators|remove_collaborator",
        "parameters": {
          "resource_type": "List or ListItem",
          "resource_id": "UUID if specified or can be determined",
          "resource_title": "title if resource_id not found (we'll search for it)",
          "email": "email to invite/remove",
          "permission": "read or write",
          "can_invite": true/false (for delegation)
        },
        "needs_disambiguation": true/false
      }

      Examples:
      - "share my grocery list with alice@example.com" -> {"action": "invite_collaborator", "parameters": {"resource_title": "grocery list", "email": "alice@example.com", "permission": "write"}}
      - "invite bob@example.com to my project with read access" -> {"action": "invite_collaborator", "parameters": {"resource_title": "project", "email": "bob@example.com", "permission": "read"}}
      - "add carol@example.com as collaborator on list #{@user.lists.first&.id}" -> {"action": "invite_collaborator", "parameters": {"resource_id": "#{@user.lists.first&.id}", "email": "carol@example.com", "permission": "write"}}
      - "who has access to my shopping list?" -> {"action": "list_collaborators", "parameters": {"resource_title": "shopping list"}}
      - "remove dave@example.com from my todo list" -> {"action": "remove_collaborator", "parameters": {"resource_title": "todo list", "email": "dave@example.com"}}
    PROMPT

    response = call_ai_with_json_mode(prompt)
    return nil unless response

    parse_json_response(response, "collaboration analysis")
  end

  # Execute the collaboration action
  def execute_collaboration_action(analysis)
    action = analysis["action"]
    params = analysis["parameters"] || {}

    # Convert string keys to symbols
    params = params.transform_keys(&:to_sym)

    # If we have a resource_title but no resource_id, search for it
    if params[:resource_title].present? && params[:resource_id].blank?
      search_result = @collaboration_tools.list_resources_for_disambiguation(
        resource_type: params[:resource_type] || "List",
        search_term: params[:resource_title]
      )

      if search_result[:success] && search_result[:single_match]
        params[:resource_id] = search_result[:resource][:id]
        params[:resource_type] = search_result[:resource][:type]
      elsif search_result[:success] && search_result[:multiple_matches]
        # Return disambiguation result
        return search_result
      else
        return {
          success: false,
          error: "Could not find a list or item matching '#{params[:resource_title]}'"
        }
      end
    end

    log_debug "Executing collaboration action: #{action}"

    case action
    when "invite_collaborator"
      @collaboration_tools.invite_collaborator(**params.slice(:resource_type, :resource_id, :email, :permission, :can_invite))
    when "list_resources_for_disambiguation"
      @collaboration_tools.list_resources_for_disambiguation(**params.slice(:resource_type, :search_term))
    when "list_collaborators"
      @collaboration_tools.list_collaborators(**params.slice(:resource_type, :resource_id))
    when "remove_collaborator"
      @collaboration_tools.remove_collaborator(**params.slice(:resource_type, :resource_id, :email))
    else
      {
        success: false,
        error: "Unknown collaboration action: #{action}"
      }
    end
  rescue => e
    log_error "Error executing collaboration action: #{e.message}"
    {
      success: false,
      error: "Failed to execute collaboration action: #{e.message}"
    }
  end

# ============================================================================
# Update create_user_from_analysis to use symbol keys

def create_user_from_analysis(params)
  # Validate permissions
  unless @user.admin?
    return {
      success: false,
      error: "Only administrators can create users.",
      unauthorized: true
    }
  end

  # Validate required parameters (use symbol keys)
  unless params[:email].present?
    return {
      success: false,
      error: "Email is required to create a user.",
      errors: [ "Email cannot be blank" ]
    }
  end

  # Check if user already exists
  if User.exists?(email: params[:email])
    return {
      success: false,
      error: "User with this email already exists.",
      errors: [ "Email has already been taken" ]
    }
  end

  begin
    # Create the user WITHOUT generating password
    new_user = User.new(
      name: params[:name] || params[:email].split("@").first.capitalize,
      email: params[:email],
      bio: params[:bio],
      locale: params[:locale] || "en",
      timezone: params[:timezone] || "UTC",
      admin_notes: params[:admin_notes]
    )

    # Generate temp password using User model method
    new_user.generate_temp_password

    if new_user.save
      # Add admin role if requested
      new_user.add_role(:admin) if params[:make_admin] == true

      # Send admin invitation email
      new_user.send_admin_invitation!

      log_debug "✓ User created: #{new_user.email}"

      {
        success: true,
        message: "User #{new_user.email} created successfully.",
        user: {
          id: new_user.id,
          name: new_user.name,
          email: new_user.email,
          status: new_user.status,
          admin: new_user.admin?,
          sign_in_count: new_user.sign_in_count,
          last_sign_in_at: new_user.last_sign_in_at
        }
      }
    else
      log_error "Failed to create user: #{new_user.errors.full_messages.join(', ')}"

      {
        success: false,
        error: "Failed to create user.",
        errors: new_user.errors.full_messages
      }
    end
  rescue => e
    log_error "Error in create_user_from_analysis: #{e.message}", e

    {
      success: false,
      error: "An unexpected error occurred while creating the user.",
      errors: [ e.message ]
    }
  end
end

  # Build response for user management actions
  def build_user_management_response(um_result)
    if um_result[:success]
      response = um_result[:message] || "Action completed successfully."

      # Add user details if present
      if um_result[:user]
        user_info = um_result[:user]
        response += "\n\n**User Details:**\n"
        response += "- Name: #{user_info[:name]}\n"
        response += "- Email: #{user_info[:email]}\n"
        response += "- Status: #{user_info[:status]}\n"
        response += "- Admin: #{user_info[:admin] ? 'Yes' : 'No'}\n"
        response += "- Sign-in count: #{user_info[:sign_in_count]}\n"
        response += "- Last sign-in: #{user_info[:last_sign_in_at] ? user_info[:last_sign_in_at].strftime('%Y-%m-%d %H:%M') : 'Never'}\n"
      end

      # Add user list if present
      if um_result[:users]
        response += "\n\n**Users (#{um_result[:count]} of #{um_result[:total_count]}):**\n"
        um_result[:users].each do |user_info|
          response += "\n- #{user_info[:name]} (#{user_info[:email]})"
          response += " - #{user_info[:status].upcase}"
          response += " - Admin" if user_info[:admin]
        end
      end

      # Add statistics if present
      if um_result[:statistics]
        stats = um_result[:statistics]
        response += "\n\n**User Statistics:**\n"
        response += "- Total users: #{stats[:total_users]}\n"
        response += "- Active: #{stats[:active_users]}\n"
        response += "- Suspended: #{stats[:suspended_users]}\n"
        response += "- Deactivated: #{stats[:deactivated_users]}\n"
        response += "- Pending verification: #{stats[:pending_verification]}\n"
        response += "- Admins: #{stats[:admin_users]}\n"
        response += "- Signed in today: #{stats[:users_signed_in_today]}\n"
        response += "- Signed in this week: #{stats[:users_signed_in_this_week]}\n"
      end

      response
    else
      error_msg = um_result[:error] || "Action failed"

      if um_result[:unauthorized]
        "❌ #{error_msg}. You don't have permission to perform this action."
      elsif um_result[:errors]
        "❌ #{error_msg}\n\nErrors:\n" + um_result[:errors].map { |e| "- #{e}" }.join("\n")
      else
        "❌ #{error_msg}"
      end
    end
  end

  def build_collaboration_response(collab_result)
    if collab_result[:success]
      response = collab_result[:message] || "Collaboration action completed successfully."

      # Handle invitation result
      if collab_result[:invitee]
        response += "\n\n**Collaboration Details:**\n"
        response += "- Resource: #{collab_result[:resource][:title]}\n" if collab_result[:resource]
        response += "- Invited: #{collab_result[:invitee]}\n"
        response += "- Permission: #{collab_result[:permission]}\n"
        response += "- Can invite others: #{collab_result[:can_invite_others] ? 'Yes' : 'No'}\n"
      end

      # Handle list collaborators result
      if collab_result[:collaborators]
        response += "\n\n**Current Collaborators (#{collab_result[:total_collaborators]}):**\n"
        collab_result[:collaborators].each do |collaborator|
          response += "\n- #{collaborator[:name]} (#{collaborator[:email]})"
          response += " - #{collaborator[:permission].upcase}"
          response += " - Can invite others" if collaborator[:can_invite_others]
        end

        if collab_result[:pending_invitations]&.any?
          response += "\n\n**Pending Invitations (#{collab_result[:pending_count]}):**\n"
          collab_result[:pending_invitations].each do |inv|
            response += "\n- #{inv[:email]}"
            response += " - #{inv[:permission].upcase}"
            response += " - Invited by #{inv[:invited_by]}"
          end
        end
      end

      # Handle disambiguation result
      if collab_result[:multiple_matches]
        response = "I found #{collab_result[:resources].size} matching resources. Please specify which one:\n\n"
        collab_result[:resources].each_with_index do |resource, index|
          response += "#{index + 1}. #{resource[:title]}"
          response += " (#{resource[:type]})"
          response += " - #{resource[:list_title]}" if resource[:list_title]
          response += "\n"
        end
      end

      response
    else
      error_msg = collab_result[:error] || "Collaboration action failed"
      "❌ #{error_msg}"
    end
  end

  def log_debug(message)
    Rails.logger.debug "[AI_AGENT] #{message}"
  end

  def log_warning(message)
    Rails.logger.warn "[AI_AGENT] ⚠️  #{message}"
  end

  def log_error(message, exception = nil)
    Rails.logger.error "[AI_AGENT] ❌ #{message}"
    if exception
      Rails.logger.error exception.backtrace[0..5].join("\n")
    end
  end
end
