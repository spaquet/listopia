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

    # Step 0: Content moderation (if enabled)
    moderation_result = moderate_content(message_content)
    if moderation_result[:blocked]
      return handle_blocked_content(moderation_result)
    end

    # Add user message to chat
    user_message = @chat.add_message(
      role: "user",
      content: message_content,
      message_type: "text"
    )

    # Execute multi-step AI agent workflow
    result = execute_ai_workflow

    # Create response message
    response_message = @chat.add_message(
      role: "assistant",
      content: result[:message],
      message_type: "text"
    )

    {
      message: response_message,
      lists_created: result[:lists_created],
      items_created: result[:items_created]
    }

  rescue => e
    Rails.logger.error "AI Agent error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")

    error_message = @chat.add_message(
      role: "assistant",
      content: "I encountered an error processing your request. Please try again.",
      message_type: "text"
    )

    { message: error_message, lists_created: [], items_created: [] }
  end

  private

  def find_or_create_chat
    existing = @user.chats.where(status: "active").order(last_message_at: :desc, created_at: :desc).first
    return existing if existing

    @user.chats.create!(
      title: "AI Chat - #{Time.current.strftime('%m/%d %H:%M')}",
      status: "active",
      conversation_state: "stable"
    )
  end

  # Content moderation using RubyLLM
  def moderate_content(content)
    # Check if moderation is enabled via environment variable (defaults to true)
    return { blocked: false } unless moderation_enabled?

    begin
      moderation_result = RubyLLM.moderate(content)

      if moderation_result.flagged?
        Rails.logger.warn "Content flagged by moderation: #{moderation_result.flagged_categories.join(', ')}"

        {
          blocked: true,
          categories: moderation_result.flagged_categories,
          message: generate_moderation_message(moderation_result.flagged_categories),
          scores: moderation_result.category_scores
        }
      else
        Rails.logger.debug "Content passed moderation checks"
        { blocked: false }
      end

    rescue RubyLLM::ConfigurationError => e
      Rails.logger.error "Moderation not configured: #{e.message}"
      # Fallback: allow content but log the issue
      { blocked: false, warning: "Moderation unavailable" }

    rescue RubyLLM::RateLimitError => e
      Rails.logger.warn "Moderation rate limited: #{e.message}"
      # Fallback: allow content but log rate limit
      { blocked: false, warning: "Moderation rate limited" }

    rescue RubyLLM::Error => e
      Rails.logger.error "Moderation failed: #{e.message}"
      # Fallback: allow content but log error
      { blocked: false, warning: "Moderation error" }
    end
  end

  def moderation_enabled?
    # Default to true if environment variable is not set
    ENV.fetch("LISTOPIA_USE_MODERATION", "true").downcase == "true"
  end

  def generate_moderation_message(flagged_categories)
    # Provide user-friendly, specific feedback based on flagged categories
    case
    when flagged_categories.include?("harassment") || flagged_categories.include?("harassment/threatening")
      "I can't help create lists with content that could be used to harass others. Please try a different request focused on positive organization and productivity."

    when flagged_categories.include?("hate") || flagged_categories.include?("hate/threatening")
      "I'm designed to help with positive list creation and organization. Please rephrase your request without targeting any groups or individuals."

    when flagged_categories.include?("violence") || flagged_categories.include?("violence/graphic")
      "I can't create lists involving violent content. Let me help you organize something constructive instead - perhaps a project, travel plans, or learning goals?"

    when flagged_categories.include?("self-harm") || flagged_categories.include?("self-harm/intent") || flagged_categories.include?("self-harm/instructions")
      "I'm concerned about your request and can't create content related to self-harm. If you're going through a difficult time, please consider reaching out to a mental health professional or crisis helpline. I'm here to help with positive organization and planning."

    when flagged_categories.include?("sexual") || flagged_categories.include?("sexual/minors")
      "I can't create lists with sexual content. Let me help you organize something else - perhaps work projects, hobbies, or learning materials?"

    else
      "Your request doesn't align with our content guidelines. I'm here to help you create productive, positive lists for organization and planning. Could you try rephrasing your request?"
    end
  end

  def handle_blocked_content(moderation_result)
    # Create a polite but firm response message using regular chat system
    response_message = @chat.add_message(
      role: "assistant",
      content: moderation_result[:message],
      message_type: "text"
    )

    # Log the incident for monitoring
    Rails.logger.info "Blocked content creation attempt - Categories: #{moderation_result[:categories].join(', ')}, User: #{@user.id}"

    {
      message: response_message,
      lists_created: [],
      items_created: [],
      moderation_blocked: true,
      flagged_categories: moderation_result[:categories]
    }
  end

  def execute_ai_workflow
    # Step 1: Analyze intent
    intent_data = analyze_user_intent
    return fallback_creation if intent_data.nil?

    # Step 2: Extract entities based on intent
    entities = extract_entities_with_ai(intent_data)
    return fallback_creation if entities.nil?

    # Step 3: Create execution plan
    plan = create_execution_plan(intent_data, entities)
    return fallback_creation if plan.nil?

    # Step 4: Execute the plan
    execute_plan(plan)
  end

  # Step 1: AI analyzes user intent
  def analyze_user_intent
    prompt = <<~PROMPT
      Analyze this user message and determine their intent for list management:

      Message: "#{@current_message}"

      Respond with JSON only (no markdown, no extra text):
      {
        "intent_type": "grocery_shopping|event_planning|travel_planning|project_management|reading_list|roadshow_planning|generic_list",
        "complexity": "simple|moderate|complex",
        "entities_needed": ["cities", "items", "books", "tasks", "attendees"],
        "structure_type": "simple_list|hierarchical_lists|categorized_lists",
        "estimated_count": 5,
        "keywords": ["key", "words", "found"]
      }
    PROMPT

    # Use RubyLLM through the existing chat
    temp_chat = Chat.new(user: @user, title: "Intent Analysis")
    response = temp_chat.ask([
      {
        role: "system",
        content: "You are an intelligent task analysis assistant. Always respond with valid JSON only."
      },
      { role: "user", content: prompt }
    ])

    parse_json_response(response.content, "intent analysis")
  rescue => e
    Rails.logger.error "Intent analysis failed: #{e.message}"
    nil
  end

  # Step 2: AI extracts specific entities
  def extract_entities_with_ai(intent_data)
    entities_needed = intent_data["entities_needed"] || []

    prompt = <<~PROMPT
      Extract specific entities from this message. Extract ALL entities mentioned, preserving full names:

      Message: "#{@current_message}"
      Intent: #{intent_data['intent_type']}
      Extract: #{entities_needed.join(', ')}

      Respond with JSON only (no markdown, no extra text):
      {
        "cities": ["San Francisco", "New York", "Austin"],
        "items": ["2 apples", "milk", "chocolate"],
        "books": ["Complete Book Title 1", "Author Name"],
        "tasks": ["Complete task description"],
        "quantities": {"books": 5, "cities": 8},
        "categories": ["energizing", "business"],
        "title_suggestion": "Suggested List Title"
      }

      Include only entity types that exist in the message. Preserve complete names and quantities.
    PROMPT

    temp_chat = Chat.new(user: @user, title: "Entity Extraction")
    response = temp_chat.ask([
      {
        role: "system",
        content: "You are a precise entity extraction specialist. Always respond with valid JSON only."
      },
      { role: "user", content: prompt }
    ])

    parse_json_response(response.content, "entity extraction")
  rescue => e
    Rails.logger.error "Entity extraction failed: #{e.message}"
    nil
  end

  # Step 3: AI creates execution plan
  def create_execution_plan(intent_data, entities)
    prompt = <<~PROMPT
      Create a detailed execution plan for list creation:

      Intent: #{intent_data.to_json}
      Entities: #{entities.to_json}

      Respond with JSON only (no markdown, no extra text):
      {
        "structure_type": "simple_list|hierarchical_lists",
        "main_list": {
          "title": "Main List Title",
          "description": "Optional description",
          "list_type": "personal|professional"
        },
        "items": [
          {
            "title": "Item title",
            "item_type": "task|shopping|learning|travel",
            "priority": "low|medium|high"
          }
        ],
        "sub_lists": [
          {
            "title": "Sub-list title",
            "items": [
              {
                "title": "Sub-item title",
                "item_type": "task",
                "priority": "medium"
              }
            ]
          }
        ]
      }

      Create comprehensive plans based on the extracted entities.
    PROMPT

    temp_chat = Chat.new(user: @user, title: "Planning")
    response = temp_chat.ask([
      {
        role: "system",
        content: "You are a project planning expert. Always respond with valid JSON only."
      },
      { role: "user", content: prompt }
    ])

    parse_json_response(response.content, "execution planning")
  rescue => e
    Rails.logger.error "Execution planning failed: #{e.message}"
    nil
  end

  # Step 4: Execute the AI-generated plan
  def execute_plan(plan)
    case plan["structure_type"]
    when "simple_list"
      execute_simple_list_plan(plan)
    when "hierarchical_lists"
      execute_hierarchical_plan(plan)
    else
      execute_simple_list_plan(plan) # Default fallback
    end
  rescue => e
    Rails.logger.error "Plan execution failed: #{e.message}"
    fallback_creation
  end

  def execute_simple_list_plan(plan)
    lists_created = []
    items_created = []

    # Create main list
    main_list_config = plan["main_list"] || {}
    list = @user.lists.create!(
      title: main_list_config["title"] || "New List",
      description: main_list_config["description"],
      status: "active",
      list_type: main_list_config["list_type"] || "personal"
    )
    lists_created << list

    # Add items
    items = plan["items"] || []
    items.each_with_index do |item_config, index|
      item = list.list_items.create!(
        title: item_config["title"],
        completed: false,
        priority: item_config["priority"] || "medium",
        item_type: item_config["item_type"] || "task",
        position: index
      )
      items_created << item
    end

    {
      message: "Created '#{list.title}' with #{items_created.count} items",
      lists_created: lists_created,
      items_created: items_created
    }
  end

  def execute_hierarchical_plan(plan)
    lists_created = []
    items_created = []

    # Create main list
    main_list_config = plan["main_list"] || {}
    main_list = @user.lists.create!(
      title: main_list_config["title"] || "Project Planning",
      description: main_list_config["description"],
      status: "active",
      list_type: main_list_config["list_type"] || "professional"
    )
    lists_created << main_list

    # Add main list items if any
    main_items = plan["items"] || []
    main_items.each_with_index do |item_config, index|
      item = main_list.list_items.create!(
        title: item_config["title"],
        completed: false,
        priority: item_config["priority"] || "medium",
        item_type: item_config["item_type"] || "task",
        position: index
      )
      items_created << item
    end

    # Create sub-lists
    sub_lists = plan["sub_lists"] || []
    sub_lists.each do |sub_list_config|
      sub_list = @user.lists.create!(
        title: sub_list_config["title"],
        parent_list: main_list,
        status: "active",
        list_type: main_list_config["list_type"] || "professional"
      )
      lists_created << sub_list

      # Add items to sub-list
      sub_items = sub_list_config["items"] || []
      sub_items.each_with_index do |item_config, index|
        item = sub_list.list_items.create!(
          title: item_config["title"],
          completed: false,
          priority: item_config["priority"] || "medium",
          item_type: item_config["item_type"] || "task",
          position: index
        )
        items_created << item
      end
    end

    {
      message: "Created '#{main_list.title}' with #{lists_created.count - 1} sub-lists and #{items_created.count} total items",
      lists_created: lists_created,
      items_created: items_created
    }
  end

  # Fallback for when AI steps fail
  def fallback_creation
    # Simple extraction based on keywords as last resort
    if @current_message.downcase.include?("grocery")
      create_simple_grocery_list
    elsif @current_message.downcase.include?("roadshow") || @current_message.downcase.include?("cities")
      create_simple_roadshow_list
    elsif @current_message.downcase.include?("book")
      create_simple_book_list
    else
      create_generic_list
    end
  end

  def create_simple_grocery_list
    list = @user.lists.create!(
      title: "Grocery List",
      status: "active",
      list_type: "personal"
    )

    default_items = [ "Milk", "Bread", "Eggs" ]
    items_created = []

    default_items.each_with_index do |item_name, index|
      item = list.list_items.create!(
        title: item_name,
        completed: false,
        priority: "medium",
        item_type: "shopping",
        position: index
      )
      items_created << item
    end

    {
      message: "Created grocery list with #{items_created.count} items",
      lists_created: [ list ],
      items_created: items_created
    }
  end

  def create_simple_roadshow_list
    main_list = @user.lists.create!(
      title: "Roadshow Planning",
      status: "active",
      list_type: "professional"
    )

    default_cities = [ "San Francisco", "New York", "Chicago" ]
    lists_created = [ main_list ]
    items_created = []

    default_cities.each do |city|
      sub_list = @user.lists.create!(
        title: "#{city} Stop",
        parent_list: main_list,
        status: "active",
        list_type: "professional"
      )
      lists_created << sub_list

      [ "Book venue", "Arrange travel" ].each_with_index do |task, index|
        item = sub_list.list_items.create!(
          title: task,
          completed: false,
          priority: "medium",
          item_type: "task",
          position: index
        )
        items_created << item
      end
    end

    {
      message: "Created roadshow planning with #{default_cities.count} city stops",
      lists_created: lists_created,
      items_created: items_created
    }
  end

  def create_simple_book_list
    list = @user.lists.create!(
      title: "Reading List",
      status: "active",
      list_type: "personal"
    )

    default_books = [ "Sapiens", "Atomic Habits", "The Alchemist" ]
    items_created = []

    default_books.each_with_index do |book, index|
      item = list.list_items.create!(
        title: book,
        completed: false,
        priority: "medium",
        item_type: "learning",
        position: index
      )
      items_created << item
    end

    {
      message: "Created reading list with #{items_created.count} books",
      lists_created: [ list ],
      items_created: items_created
    }
  end

  def create_generic_list
    list = @user.lists.create!(
      title: "New List",
      status: "active",
      list_type: "personal"
    )

    {
      message: "Created new list - ready for you to add items",
      lists_created: [ list ],
      items_created: []
    }
  end

  # Helper method to parse JSON responses safely
  def parse_json_response(response_text, step_name)
    # Clean response text
    cleaned = response_text.strip

    # Remove markdown code blocks if present
    cleaned = cleaned.gsub(/```json\n?/, "").gsub(/```\n?/, "")

    # Find JSON content
    json_start = cleaned.index("{")
    json_end = cleaned.rindex("}")

    return nil unless json_start && json_end && json_end > json_start

    json_text = cleaned[json_start..json_end]
    JSON.parse(json_text)

  rescue JSON::ParserError => e
    Rails.logger.error "Failed to parse JSON for #{step_name}: #{e.message}"
    Rails.logger.error "Response text: #{response_text.truncate(200)}"
    nil
  end
end
