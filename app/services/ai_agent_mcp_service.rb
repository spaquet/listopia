# app/services/ai_agent_mcp_service.rb
class AiAgentMcpService
  attr_reader :user, :context, :chat, :current_message, :extracted_data

  def initialize(user:, context: {})
    @user = user
    @context = context
    @chat = find_or_create_chat
    @extracted_data = {}
  end

  # Main entry point for processing user messages
  def process_message(message_content)
    @current_message = message_content
    log_debug "=" * 80
    log_debug "NEW MESSAGE: #{message_content}"
    log_debug "=" * 80

    # STEP 1: Content moderation (RubyLLM 1.8+ moderation API)
    moderation_result = moderate_content(message_content)
    if moderation_result[:blocked]
      log_debug "MODERATION: Content blocked - #{moderation_result[:categories].join(', ')}"
      return handle_blocked_content(moderation_result)
    end
    log_debug "MODERATION: Content passed"

    # Add user message to chat
    @chat.add_message(
      role: "user",
      content: message_content,
      message_type: "text"
    )

    # Execute multi-step AI workflow
    result = execute_multi_step_workflow

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

  # ============================================================================
  # STEP 1: CONTENT MODERATION
  # Uses RubyLLM 1.8+ moderation API to check content safety
  # ============================================================================

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
      # Fail open - allow request to proceed if moderation fails
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
    response_message = @chat.add_message(
      role: "assistant",
      content: moderation_result[:message],
      message_type: "text"
    )

    Rails.logger.info "Blocked content - Categories: #{moderation_result[:categories].join(', ')}, User: #{@user.id}"

    {
      message: response_message,
      lists_created: [],
      items_created: [],
      moderation_blocked: true,
      flagged_categories: moderation_result[:categories]
    }
  end

  # ============================================================================
  # MULTI-STEP AI WORKFLOW
  # Step 1: Moderation (done above)
  # Step 2: Categorize as Professional or Personal
  # Step 3: Determine structure (simple list, list with sublists, mixed)
  # Step 4: Extract all items with correct quantities
  # Step 5: Execute the plan and create lists/items
  # ============================================================================

  def execute_multi_step_workflow
    log_debug "\n" + "=" * 80
    log_debug "STARTING MULTI-STEP AI WORKFLOW"
    log_debug "=" * 80

    # STEP 2: Categorize the list type
    categorization = categorize_list_type
    return handle_workflow_failure("categorization") if categorization.nil?

    log_debug "STEP 2 RESULT: #{categorization.inspect}"

    # STEP 3: Determine structure complexity
    structure = determine_structure
    return handle_workflow_failure("structure determination") if structure.nil?

    log_debug "STEP 3 RESULT: #{structure.inspect}"

    # STEP 4: Extract ALL items based on structure
    items_data = extract_all_items(structure)
    return handle_workflow_failure("item extraction") if items_data.nil?

    log_debug "STEP 4 RESULT: Extracted #{items_data['total_items']} total items"

    # STEP 5: Execute the plan
    execution_result = execute_creation_plan(categorization, structure, items_data)

    log_debug "STEP 5 RESULT: Created #{execution_result[:lists_created].count} lists, #{execution_result[:items_created].count} items"
    log_debug "=" * 80 + "\n"

    execution_result

  rescue => e
    log_error "Workflow failed: #{e.message}", e
    handle_workflow_failure("workflow execution")
  end

  # ============================================================================
  # STEP 2: CATEGORIZATION
  # AI determines if this is a professional or personal list
  # Completely generic - can handle ANY type of list user requests
  # ============================================================================

  def categorize_list_type
    log_debug "\n--- STEP 2: CATEGORIZATION ---"

    prompt = <<~PROMPT
      Analyze this user request and categorize it. This is a task management system that can handle ANY type of list.

      User Request: "#{@current_message}"

      Determine:
      1. Is this PROFESSIONAL (work, business, projects) or PERSONAL (home, hobbies, personal tasks)?
      2. What would be an appropriate, descriptive title?
      3. What is the general domain or context?

      Respond with ONLY valid JSON (no markdown):
      {
        "list_type": "professional|personal",
        "suggested_title": "Clear, descriptive title for the list",
        "domain": "Brief description of what this list is about",
        "reasoning": "Brief explanation of categorization"
      }

      Examples:
      - "grocery list" → personal, "Grocery Shopping List", "food and household items"
      - "roadshow planning" → professional, "Roadshow Planning", "multi-city business event"
      - "books to read" → personal, "Reading List", "books and learning materials"
      - "home renovation tasks" → personal, "Home Renovation Project", "house improvement"
      - "Q4 marketing campaign" → professional, "Q4 Marketing Campaign", "business marketing"
      - "wedding planning" → personal, "Wedding Planning", "event organization"
      - "server migration checklist" → professional, "Server Migration", "IT infrastructure"
      - "travel itinerary for Europe trip" → personal, "Europe Trip Itinerary", "travel plans and activities"
      - "project launch tasks" → professional, "Project Launch", "product launch activities"
      - "fitness goals and workouts" → personal, "Fitness Goals", "health and exercise routines"
      - "client onboarding steps" → professional, "Client Onboarding", "new client setup process"
      - "gardening to-do list" → personal, "Gardening Tasks", "garden maintenance and planting"
      - "software development sprint" → professional, "Development Sprint", "software project tasks"
      - "market research topics" → professional, "Market Research", "business analysis"
      - "marketing ideas" → professional, "Marketing Ideas", "business promotion strategies"
      - "product launch checklist" → professional, "Product Launch Checklist", "steps for launching a product"
      - "vacation packing list" → personal, "Vacation Packing List", "items to pack for a trip"

      Be flexible and creative with titles. Match the user's intent and language.
    PROMPT

    response = call_ai_step("categorization", prompt, temperature: 0.3)
    return nil unless response

    result = parse_json_response(response, "categorization")

    if result
      log_debug "Categorized as: #{result['list_type']}"
      log_debug "Suggested title: #{result['suggested_title']}"
      log_debug "Domain: #{result['domain']}"
    end

    result
  end

  # ============================================================================
  # STEP 3: STRUCTURE DETERMINATION
  # AI decides if this needs simple list, sublists, or mixed structure
  # ============================================================================

  def determine_structure
    log_debug "\n--- STEP 3: STRUCTURE DETERMINATION ---"

    prompt = <<~PROMPT
      Analyze this request to determine the list structure needed:

      User Request: "#{@current_message}"

      Determine:
      1. Does this need a SIMPLE list (just items in one list)?
      2. Does it need HIERARCHICAL structure (main list + sublists)?
      3. Does it need MIXED (some items in main list + sublists)?

      Examples:
      - "grocery list with apples, milk" → SIMPLE (one flat list)
      - "roadshow in NYC, SF, Austin" → HIERARCHICAL (main + city sublists)
      - "project with tasks and weekly check-ins" → MIXED (some main items + sublists)

      Respond with ONLY valid JSON (no markdown):
      {
        "structure_type": "simple|hierarchical|mixed",
        "needs_sublists": true|false,
        "sublist_criteria": "What determines sublists (cities, phases, categories, etc)",
        "reasoning": "Why this structure"
      }
    PROMPT

    response = call_ai_step("structure_determination", prompt, temperature: 0.3)
    return nil unless response

    result = parse_json_response(response, "structure determination")

    if result
      log_debug "Structure: #{result['structure_type']}"
      log_debug "Needs sublists: #{result['needs_sublists']}"
      log_debug "Sublist criteria: #{result['sublist_criteria']}" if result["sublist_criteria"]
    end

    result
  end

  # ============================================================================
  # STEP 4: ITEM EXTRACTION
  # AI extracts EVERY item mentioned, respecting quantities and structure
  # This is the CRITICAL step - must get ALL items
  # ============================================================================

  def extract_all_items(structure)
    log_debug "\n--- STEP 4: ITEM EXTRACTION ---"

    # Adjust prompt based on structure type
    if structure["structure_type"] == "hierarchical" || structure["needs_sublists"]
      extract_hierarchical_items(structure)
    else
      extract_simple_items
    end
  end

  # Extract items for a simple flat list
  def extract_simple_items
    log_debug "Extracting items for SIMPLE list structure..."

    prompt = <<~PROMPT
      Extract EVERY item from this request. Each item must be separate.
      This is a flexible task management system - lists can be about ANYTHING.

      User Request: "#{@current_message}"

      CRITICAL RULES:
      1. Each comma-separated item = ONE entry
      2. "2 apples, milk, chocolate, 1 bottle" = 4 separate items
      3. If they say "5 books", generate 5 SPECIFIC book recommendations
      4. If they say "10 marketing tasks", generate 10 SPECIFIC marketing tasks
      5. Include quantities in titles ("2 apples", "1 bottle of water")
      6. NEVER combine items
      7. NEVER truncate the list
      8. Be specific and actionable for each item

      Count carefully: "item1, item2, and item3" = 3 items (not 2!)

      Respond with ONLY valid JSON (no markdown):
      {
        "items": [
          {
            "title": "First item with quantity or clear description",
            "description": "Optional additional details or context",
            "priority": "low|medium|high"
          },
          {
            "title": "Second item with quantity or clear description",
            "description": "Optional additional details or context",
            "priority": "low|medium|high"
          }
        ],
        "total_items": <exact count>,
        "verification": {
          "items_in_original_request": <count from analysis>,
          "items_in_response": <must match total_items>,
          "all_items_included": true
        }
      }

      EXAMPLES:

      Request: "grocery list with 2 apples, milk, chocolate and 1 bottle of water"
      Response must have 4 items:
      {
        "items": [
          {"title": "2 apples", "description": "", "priority": "medium"},
          {"title": "Milk", "description": "", "priority": "medium"},
          {"title": "Chocolate", "description": "", "priority": "medium"},
          {"title": "1 bottle of water", "description": "", "priority": "medium"}
        ],
        "total_items": 4,
        "verification": {"items_in_original_request": 4, "items_in_response": 4, "all_items_included": true}
      }

      Request: "5 energizing books to read"
      Response must have 5 specific books:
      {
        "items": [
          {"title": "Atomic Habits by James Clear", "description": "Practical strategies for building good habits", "priority": "medium"},
          {"title": "The Power of Now by Eckhart Tolle", "description": "Mindfulness and present-moment awareness", "priority": "medium"},
          {"title": "Sapiens by Yuval Noah Harari", "description": "Human history and evolution", "priority": "medium"},
          {"title": "Deep Work by Cal Newport", "description": "Focus and productivity in a distracted world", "priority": "medium"},
          {"title": "Mindset by Carol Dweck", "description": "Growth mindset psychology", "priority": "medium"}
        ],
        "total_items": 5,
        "verification": {"items_in_original_request": 5, "items_in_response": 5, "all_items_included": true}
      }

      Request: "7 tasks for launching a product"
      Response must have 7 specific tasks:
      {
        "items": [
          {"title": "Define target audience and personas", "description": "Research and document ideal customer profiles", "priority": "high"},
          {"title": "Create product positioning and messaging", "description": "Develop key value propositions", "priority": "high"},
          {"title": "Build landing page and website", "description": "Design and launch product website", "priority": "high"},
          {"title": "Set up analytics and tracking", "description": "Implement GA4, mixpanel, or similar", "priority": "medium"},
          {"title": "Plan and execute beta testing program", "description": "Recruit beta users and gather feedback", "priority": "high"},
          {"title": "Develop go-to-market strategy", "description": "Plan launch channels and timeline", "priority": "high"},
          {"title": "Prepare customer support resources", "description": "Create docs, FAQs, and support workflow", "priority": "medium"}
        ],
        "total_items": 7,
        "verification": {"items_in_original_request": 7, "items_in_response": 7, "all_items_included": true}
      }

      Be creative and specific. Generate appropriate items for whatever the user asks for.
    PROMPT

    response = call_ai_step("item_extraction", prompt, temperature: 0.2, max_tokens: 3000)
    return nil unless response

    result = parse_json_response(response, "item extraction")

    if result
      actual_count = result["items"]&.length || 0
      claimed_count = result["total_items"] || 0

      log_debug "Extracted #{actual_count} items (claimed: #{claimed_count})"

      if actual_count != claimed_count
        log_warning "MISMATCH: Actual items (#{actual_count}) != claimed total (#{claimed_count})"
      end

      # Log each item for verification
      result["items"]&.each_with_index do |item, idx|
        log_debug "  Item #{idx + 1}: #{item['title']}"
      end

      # Verify against user's request
      if result["verification"]
        log_debug "Verification: #{result['verification'].inspect}"
      end
    end

    result
  end

  # Extract items for hierarchical structure (list with sublists)
  def extract_hierarchical_items(structure)
    log_debug "Extracting items for HIERARCHICAL structure..."
    log_debug "Sublist criteria: #{structure['sublist_criteria']}"

    prompt = <<~PROMPT
      Extract items for a hierarchical structure (main list + sublists).
      This is a flexible task management system - can handle ANY domain.

      User Request: "#{@current_message}"
      Sublist Criteria: #{structure['sublist_criteria']}

      Structure this as:
      - Main list (optional items that don't belong to sublists - overview tasks, general items)
      - Multiple sublists (based on the criteria: cities, phases, categories, teams, etc.)
      - Each sublist has its own specific items

      CRITICAL RULES:
      1. Identify ALL sublists needed based on the criteria
      2. For each sublist, generate appropriate, specific items
      3. Count items carefully
      4. If they mention specific entities (cities, phases, teams), create one sublist per entity
      5. Generate realistic, actionable items for each context
      6. Be creative but practical

      Respond with ONLY valid JSON (no markdown):
      {
        "main_list_items": [
          {
            "title": "Overview or preparation task",
            "description": "Optional context",
            "priority": "high|medium|low"
          }
        ],
        "sublists": [
          {
            "sublist_title": "First sublist name (be specific)",
            "items": [
              {
                "title": "Specific item for this sublist",
                "description": "Optional details",
                "priority": "high|medium|low"
              },
              {
                "title": "Another specific item for this sublist",
                "description": "Optional details",
                "priority": "high|medium|low"
              }
            ]
          },
          {
            "sublist_title": "Second sublist name (be specific)",
            "items": [...]
          }
        ],
        "total_sublists": <count>,
        "total_items": <count across all lists and sublists>,
        "verification": {
          "sublists_in_request": <count from user's message>,
          "sublists_in_response": <must match>,
          "all_sublists_included": true
        }
      }

      EXAMPLES:

      Request: "roadshow planning for San Francisco, New York, and Austin"
      Response must have 3 sublists (one per city):
      {
        "main_list_items": [
          {"title": "Create master presentation deck", "description": "Design slides for all stops", "priority": "high"},
          {"title": "Book travel between cities", "description": "Flights and ground transportation", "priority": "high"}
        ],
        "sublists": [
          {
            "sublist_title": "San Francisco Stop",
            "items": [
              {"title": "Book venue in San Francisco", "description": "Downtown location preferred", "priority": "high"},
              {"title": "Coordinate with SF sales team", "description": "Ensure local team participation", "priority": "medium"},
              {"title": "Arrange local transportation", "description": "Airport pickup and venue transfer", "priority": "medium"}
            ]
          },
          {
            "sublist_title": "New York Stop",
            "items": [
              {"title": "Book venue in New York", "description": "Manhattan location preferred", "priority": "high"},
              {"title": "Coordinate with NY sales team", "description": "Ensure local team participation", "priority": "medium"},
              {"title": "Arrange local transportation", "description": "Airport pickup and venue transfer", "priority": "medium"}
            ]
          },
          {
            "sublist_title": "Austin Stop",
            "items": [
              {"title": "Book venue in Austin", "description": "Downtown location preferred", "priority": "high"},
              {"title": "Coordinate with Austin sales team", "description": "Ensure local team participation", "priority": "medium"},
              {"title": "Arrange local transportation", "description": "Airport pickup and venue transfer", "priority": "medium"}
            ]
          }
        ],
        "total_sublists": 3,
        "total_items": 11,
        "verification": {"sublists_in_request": 3, "sublists_in_response": 3, "all_sublists_included": true}
      }

      Request: "software launch with 4 phases: planning, development, testing, deployment"
      Response must have 4 sublists (one per phase):
      {
        "main_list_items": [
          {"title": "Kickoff meeting with all stakeholders", "priority": "high"},
          {"title": "Set up project tracking system", "priority": "high"}
        ],
        "sublists": [
          {
            "sublist_title": "Planning Phase",
            "items": [
              {"title": "Define product requirements", "priority": "high"},
              {"title": "Create technical architecture", "priority": "high"},
              {"title": "Estimate timeline and resources", "priority": "medium"}
            ]
          },
          {
            "sublist_title": "Development Phase",
            "items": [
              {"title": "Set up development environment", "priority": "high"},
              {"title": "Implement core features", "priority": "high"},
              {"title": "Code reviews and refactoring", "priority": "medium"}
            ]
          },
          {
            "sublist_title": "Testing Phase",
            "items": [
              {"title": "Write automated tests", "priority": "high"},
              {"title": "Conduct user acceptance testing", "priority": "high"},
              {"title": "Fix bugs and issues", "priority": "high"}
            ]
          },
          {
            "sublist_title": "Deployment Phase",
            "items": [
              {"title": "Deploy to production", "priority": "high"},
              {"title": "Monitor performance and errors", "priority": "high"},
              {"title": "Gather user feedback", "priority": "medium"}
            ]
          }
        ],
        "total_sublists": 4,
        "total_items": 14,
        "verification": {"sublists_in_request": 4, "sublists_in_response": 4, "all_sublists_included": true}
      }

      Be flexible and creative. Generate appropriate sublists and items for whatever domain the user requests.
    PROMPT

    response = call_ai_step("hierarchical_extraction", prompt, temperature: 0.2, max_tokens: 4000)
    return nil unless response

    result = parse_json_response(response, "hierarchical extraction")

    if result
      sublists_count = result["sublists"]&.length || 0
      total_items = result["total_items"] || 0

      log_debug "Extracted #{sublists_count} sublists with #{total_items} total items"

      # Log sublist details
      result["sublists"]&.each_with_index do |sublist, idx|
        item_count = sublist["items"]&.length || 0
        log_debug "  Sublist #{idx + 1}: #{sublist['sublist_title']} (#{item_count} items)"
      end

      if result["verification"]
        log_debug "Verification: #{result['verification'].inspect}"
      end
    end

    result
  end

  # ============================================================================
  # STEP 5: EXECUTION
  # Create actual database records based on AI-extracted data
  # ============================================================================

  def execute_creation_plan(categorization, structure, items_data)
    log_debug "\n--- STEP 5: EXECUTION ---"
    log_debug "Creating lists and items in database..."

    lists_created = []
    items_created = []

    if structure["structure_type"] == "hierarchical" || structure["needs_sublists"]
      # Create main list + sublists
      result = create_hierarchical_lists(categorization, items_data)
    else
      # Create simple flat list
      result = create_simple_list(categorization, items_data)
    end

    log_debug "Execution complete: #{result[:lists_created].count} lists, #{result[:items_created].count} items"

    result
  end

  # Create a simple flat list with items
  def create_simple_list(categorization, items_data)
    log_debug "Creating SIMPLE list structure..."

    lists_created = []
    items_created = []

    # Create the main list
    list = @user.lists.create!(
      title: categorization["suggested_title"] || "New List",
      description: "Created via AI assistant",
      status: "active",
      list_type: categorization["list_type"] || "personal"
    )
    lists_created << list
    log_debug "Created list: #{list.title} (#{list.id})"

    # Create all items
    items = items_data["items"] || []
    log_debug "Creating #{items.length} items..."

    items.each_with_index do |item_data, index|
      begin
        item = list.list_items.create!(
          title: item_data["title"],
          completed: false,
          priority: item_data["priority"] || "medium",
          item_type: infer_item_type(categorization["category"]),
          position: index
        )
        items_created << item
        log_debug "  ✓ Created item #{index + 1}: #{item.title}"
      rescue => e
        log_error "  ✗ Failed to create item #{index + 1}: #{e.message}"
      end
    end

    {
      success: true,
      message: "Created '#{list.title}' with #{items_created.count} items",
      lists_created: lists_created,
      items_created: items_created
    }
  end

  # Create hierarchical structure (main list + sublists)
  def create_hierarchical_lists(categorization, items_data)
    log_debug "Creating HIERARCHICAL list structure..."

    lists_created = []
    items_created = []

    # Create main list
    main_list = @user.lists.create!(
      title: categorization["suggested_title"] || "Project Planning",
      description: "Created via AI assistant",
      status: "active",
      list_type: categorization["list_type"] || "professional"
    )
    lists_created << main_list
    log_debug "Created main list: #{main_list.title} (#{main_list.id})"

    # Create main list items (if any)
    main_items = items_data["main_list_items"] || []
    log_debug "Creating #{main_items.length} main list items..."

    main_items.each_with_index do |item_data, index|
      begin
        item = main_list.list_items.create!(
          title: item_data["title"],
          completed: false,
          priority: item_data["priority"] || "medium",
          item_type: infer_item_type(categorization["category"]),
          position: index
        )
        items_created << item
        log_debug "  ✓ Created main item #{index + 1}: #{item.title}"
      rescue => e
        log_error "  ✗ Failed to create main item: #{e.message}"
      end
    end

    # Create sublists
    sublists = items_data["sublists"] || []
    log_debug "Creating #{sublists.length} sublists..."

    sublists.each_with_index do |sublist_data, sublist_idx|
      begin
        sublist = @user.lists.create!(
          title: sublist_data["sublist_title"],
          parent_list: main_list,
          status: "active",
          list_type: categorization["list_type"] || "professional"
        )
        lists_created << sublist
        log_debug "  Created sublist #{sublist_idx + 1}: #{sublist.title} (#{sublist.id})"

        # Create items for this sublist
        sublist_items = sublist_data["items"] || []
        log_debug "    Creating #{sublist_items.length} items for this sublist..."

        sublist_items.each_with_index do |item_data, item_idx|
          begin
            item = sublist.list_items.create!(
              title: item_data["title"],
              completed: false,
              priority: item_data["priority"] || "medium",
              item_type: infer_item_type(categorization["category"]),
              position: item_idx
            )
            items_created << item
            log_debug "      ✓ Item #{item_idx + 1}: #{item.title}"
          rescue => e
            log_error "      ✗ Failed to create item: #{e.message}"
          end
        end
      rescue => e
        log_error "  ✗ Failed to create sublist: #{e.message}"
      end
    end

    {
      success: true,
      message: "Created '#{main_list.title}' with #{sublists.length} sublists and #{items_created.count} total items",
      lists_created: lists_created,
      items_created: items_created
    }
  end

  # ============================================================================
  # HELPER METHODS
  # ============================================================================

  # Make an AI call for a specific step with retry logic
  def call_ai_step(step_name, prompt, temperature: 0.3, max_tokens: 2000, max_retries: 2)
    retry_count = 0

    begin
      log_debug "Calling AI for #{step_name} (attempt #{retry_count + 1}/#{max_retries + 1})..."

      response = @chat.ask(
        [
          {
            role: "system",
            content: "You are a precise task management expert. Always respond with complete, valid JSON only. No markdown formatting, no extra text. Be flexible and handle any domain or type of list the user requests."
          },
          { role: "user", content: prompt }
        ],
        max_tokens: max_tokens,
        temperature: temperature
      )

      log_debug "AI response received (#{response.content.length} chars)"
      response.content

    rescue => e
      retry_count += 1
      log_error "AI call attempt #{retry_count} failed: #{e.message}"

      if retry_count <= max_retries
        sleep(retry_count * 2)  # Exponential backoff
        retry
      else
        log_error "All AI call attempts failed for #{step_name}"
        nil
      end
    end
  end

  # Parse JSON response with multiple strategies
  def parse_json_response(response_text, step_name)
    strategies = [
      # Strategy 1: Direct parse
      -> { JSON.parse(response_text.strip) },

      # Strategy 2: Remove markdown code blocks
      -> {
        cleaned = response_text.gsub(/```json\n?/, "").gsub(/```\n?/, "").strip
        JSON.parse(cleaned)
      },

      # Strategy 3: Extract JSON object with regex
      -> {
        json_match = response_text.match(/\{.*\}/m)
        return nil unless json_match
        JSON.parse(json_match[0])
      },

      # Strategy 4: Find complete JSON by counting braces
      -> {
        start_idx = response_text.index("{")
        return nil unless start_idx

        brace_count = 0
        in_string = false
        escape_next = false
        end_idx = nil

        (start_idx...response_text.length).each do |i|
          char = response_text[i]

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
        JSON.parse(response_text[start_idx..end_idx])
      }
    ]

    strategies.each_with_index do |strategy, index|
      begin
        result = strategy.call
        if result
          log_debug "JSON parsed successfully with strategy #{index + 1}"
          return result
        end
      rescue JSON::ParserError => e
        log_debug "Parse strategy #{index + 1} failed: #{e.message}"
        next
      end
    end

    log_error "All JSON parsing strategies failed for #{step_name}"
    log_error "Response preview: #{response_text.truncate(300)}"
    nil
  end

  # Handle workflow failure gracefully
  def handle_workflow_failure(failed_step)
    log_error "Workflow failed at: #{failed_step}"
    log_debug "Attempting to create minimal list as fallback..."

    # Create a minimal list using AI
    fallback_result = create_fallback_list

    if fallback_result[:success]
      fallback_result
    else
      # Last resort - empty list
      {
        success: true,
        message: "I created a list for you, but couldn't determine all the items. Please add items manually.",
        lists_created: [ create_empty_list ],
        items_created: []
      }
    end
  end

  # Create fallback list using simple AI call
  def create_fallback_list
    log_debug "Creating fallback list..."

    prompt = <<~PROMPT
      User said: "#{@current_message}"

      Create a simple list. Extract key items/tasks mentioned.
      Keep it simple - just the essential items.
      This can be ANY type of list - be flexible.

      Respond with JSON only:
      {
        "title": "Appropriate list title based on request",
        "list_type": "personal|professional",
        "items": [
          {"title": "Item 1"},
          {"title": "Item 2"}
        ]
      }
    PROMPT

    begin
      response = call_ai_step("fallback", prompt, temperature: 0.4, max_tokens: 1500)
      return { success: false } unless response

      data = parse_json_response(response, "fallback")
      return { success: false } unless data

      list = @user.lists.create!(
        title: data["title"] || "New List",
        status: "active",
        list_type: data["list_type"] || "personal"
      )

      items_created = []
      (data["items"] || []).each_with_index do |item_data, idx|
        item = list.list_items.create!(
          title: item_data["title"],
          completed: false,
          priority: "medium",
          item_type: "task",
          position: idx
        )
        items_created << item
      end

      {
        success: true,
        message: "Created '#{list.title}' with #{items_created.count} items",
        lists_created: [ list ],
        items_created: items_created
      }
    rescue => e
      log_error "Fallback creation failed: #{e.message}"
      { success: false }
    end
  end

  # Create empty list as last resort
  def create_empty_list
    @user.lists.create!(
      title: "New List",
      description: "Created via AI assistant",
      status: "active",
      list_type: "personal"
    )
  end

  # ============================================================================
  # LOGGING HELPERS
  # Comprehensive logging for debugging and troubleshooting
  # ============================================================================

  def log_debug(message)
    Rails.logger.debug "[AI_AGENT] #{message}"
  end

  def log_warning(message)
    Rails.logger.warn "[AI_AGENT] ⚠️  #{message}"
  end

  def log_error(message, exception = nil)
    Rails.logger.error "[AI_AGENT] ❌ #{message}"
    if exception
      Rails.logger.error "[AI_AGENT] Exception: #{exception.class}: #{exception.message}"
      Rails.logger.error exception.backtrace[0..5].join("\n")
    end
  end
end
