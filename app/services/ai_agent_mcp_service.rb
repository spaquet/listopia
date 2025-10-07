# app/services/ai_agent_mcp_service.rb
class AiAgentMcpService
  attr_reader :user, :context, :chat, :current_message, :extracted_data

  def initialize(user:, context: {})
    @user = user
    @context = context
    @chat = find_or_create_chat
    @extracted_data = {}
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

    # STEP 2: Categorize and extract everything in ONE call
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
      list_type: analysis["list_type"] || "personal"
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
      list_type: analysis["list_type"] || "professional"
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
        list_type: analysis["list_type"] || "professional"
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
      list_type: "personal"
    )

    {
      success: false,
      message: "I created a list for you, but couldn't extract all items. Please add items manually.",
      lists_created: [ list ],
      items_created: []
    }
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
