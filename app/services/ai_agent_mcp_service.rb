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

    # Execute consolidated AI workflow
    result = execute_consolidated_ai_workflow

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
        flagged_categories = moderation_result.categories

        {
          blocked: true,
          categories: flagged_categories,
          message: generate_moderation_message(flagged_categories)
        }
      else
        { blocked: false }
      end
    rescue => e
      Rails.logger.error "Moderation failed: #{e.message}"
      # If moderation fails, allow the request to proceed (fail open)
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

  # NEW: Consolidated AI workflow - single call approach
  def execute_consolidated_ai_workflow
    # Create comprehensive prompt that handles everything in one go
    prompt = build_comprehensive_prompt

    # Single AI call with proper configuration
    response = call_ai_with_retry(prompt)

    # Parse and execute the comprehensive response
    result = parse_and_execute_comprehensive_response(response)

    # If AI approach fails, fall back to simple creation
    return result if result[:success]

    Rails.logger.warn "Consolidated AI workflow failed, using fallback"
    fallback_creation
  end

  def build_comprehensive_prompt
    <<~PROMPT
      You are an expert list creation assistant. Analyze the user's request and create a complete, detailed list plan.

      User Request: "#{@current_message}"

      Your task is to:
      1. Understand exactly what the user wants
      2. Create ALL items they requested (don't miss any!)
      3. Provide specific, actionable items
      4. Preserve exact quantities mentioned

      CRITICAL: If the user asks for 5 books, provide exactly 5 books. If they mention specific items, include ALL of them.

      Respond with a JSON object containing the complete execution plan:

      {
        "analysis": {
          "intent_type": "grocery_shopping|reading_list|travel_planning|project_management|roadshow_planning|generic_task_list",
          "requested_quantity": <number if specified>,
          "specific_items_mentioned": ["item1", "item2"],
          "categories_or_themes": ["theme1", "theme2"],
          "complexity": "simple|moderate|complex"
        },
        "execution_plan": {
          "structure_type": "simple_list|hierarchical_lists",
          "main_list": {
            "title": "Specific descriptive title",
            "description": "Brief description",
            "list_type": "personal|professional"
          },
          "items": [
            {
              "title": "Specific item title",
              "description": "Detailed description if helpful",
              "item_type": "task|shopping|learning|travel|planning",
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
        },
        "validation": {
          "total_items_created": <number>,
          "meets_user_requirements": true|false,
          "missing_elements": []
        }
      }

      IMPORTANT RULES:
      - If user asks for N items, create exactly N items
      - Include ALL specific items mentioned by the user
      - For reading lists, provide complete book titles and authors when possible
      - For grocery lists, include specific items mentioned plus logical additions
      - For travel/roadshow lists, include all mentioned cities
      - Always aim for completeness and specificity
      - Never truncate or abbreviate lists

      Example: If user says "5 energizing books", provide exactly 5 book recommendations.
      Example: If user says "grocery list with apples, milk, bread", include those 3 plus reasonable additions.
    PROMPT
  end

  def call_ai_with_retry(prompt, max_retries: 2)
    retry_count = 0

    begin
      # Use chat with proper configuration for longer responses
      response = @chat.ask(
        [
          {
            role: "system",
            content: "You are a precise list creation expert. Always respond with complete, valid JSON that includes ALL requested items. Be thorough and never truncate responses."
          },
          {
            role: "user",
            content: prompt
          }
        ],
        # Ensure sufficient tokens for complete responses
        max_tokens: 2000,
        temperature: 0.3  # Lower temperature for more consistent results
      )

      response.content

    rescue => e
      retry_count += 1
      Rails.logger.error "AI call attempt #{retry_count} failed: #{e.message}"

      if retry_count <= max_retries
        sleep(retry_count * 2)  # Exponential backoff
        retry
      else
        Rails.logger.error "All AI call attempts failed"
        nil
      end
    end
  end

  def parse_and_execute_comprehensive_response(response_text)
    return { success: false } if response_text.blank?

    begin
      # Robust JSON parsing
      parsed_response = parse_json_robustly(response_text)
      return { success: false } unless parsed_response

      # Validate the response structure
      unless valid_comprehensive_response?(parsed_response)
        Rails.logger.error "Invalid response structure from AI"
        return { success: false }
      end

      # Execute the plan
      execution_result = execute_comprehensive_plan(parsed_response["execution_plan"])

      # Validate we created what was requested
      analysis = parsed_response["analysis"] || {}
      validation = validate_creation_completeness(execution_result, analysis)

      if validation[:complete]
        {
          success: true,
          message: execution_result[:message],
          lists_created: execution_result[:lists_created],
          items_created: execution_result[:items_created]
        }
      else
        Rails.logger.warn "Creation incomplete: #{validation[:issues].join(', ')}"
        { success: false }
      end

    rescue => e
      Rails.logger.error "Failed to parse/execute comprehensive response: #{e.message}"
      { success: false }
    end
  end

  def parse_json_robustly(response_text)
    # Multiple parsing strategies
    strategies = [
      # Strategy 1: Direct parse
      -> { JSON.parse(response_text.strip) },

      # Strategy 2: Remove markdown
      -> {
        cleaned = response_text.gsub(/```json\n?/, "").gsub(/```\n?/, "").strip
        JSON.parse(cleaned)
      },

      # Strategy 3: Extract JSON block
      -> {
        json_match = response_text.match(/\{.*\}/m)
        return nil unless json_match
        JSON.parse(json_match[0])
      },

      # Strategy 4: Find first complete JSON object
      -> {
        start_idx = response_text.index("{")
        return nil unless start_idx

        brace_count = 0
        end_idx = nil

        (start_idx...response_text.length).each do |i|
          char = response_text[i]
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
        Rails.logger.info "JSON parsed successfully with strategy #{index + 1}" if result
        return result
      rescue JSON::ParserError => e
        Rails.logger.debug "Strategy #{index + 1} failed: #{e.message}"
        next
      end
    end

    Rails.logger.error "All JSON parsing strategies failed for: #{response_text.truncate(200)}"
    nil
  end

  def valid_comprehensive_response?(parsed)
    parsed.is_a?(Hash) &&
      parsed["execution_plan"].is_a?(Hash) &&
      parsed["execution_plan"]["main_list"].is_a?(Hash) &&
      parsed["execution_plan"]["items"].is_a?(Array)
  end

  def execute_comprehensive_plan(plan)
    case plan["structure_type"]
    when "hierarchical_lists"
      execute_hierarchical_plan(plan)
    else
      execute_simple_list_plan(plan)
    end
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

    # Add ALL items from the plan
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

  def validate_creation_completeness(execution_result, analysis)
    requested_quantity = analysis["requested_quantity"]
    items_created_count = execution_result[:items_created].count

    issues = []

    # Check quantity if specified
    if requested_quantity && items_created_count < requested_quantity
      issues << "Created #{items_created_count} items but user requested #{requested_quantity}"
    end

    # Check for specific items mentioned
    specific_items = analysis["specific_items_mentioned"] || []
    if specific_items.any?
      created_titles = execution_result[:items_created].map(&:title)
      missing_items = specific_items.reject do |item|
        created_titles.any? { |title| title.downcase.include?(item.downcase) }
      end

      if missing_items.any?
        issues << "Missing specific items: #{missing_items.join(', ')}"
      end
    end

    {
      complete: issues.empty?,
      issues: issues
    }
  end

  # Fallback for when AI approach fails completely
  def fallback_creation
    # Determine fallback type based on keywords in user message
    if @current_message.downcase.include?("grocery")
      create_simple_grocery_list
    elsif @current_message.downcase.include?("book") || @current_message.downcase.include?("read")
      create_simple_book_list
    elsif @current_message.downcase.include?("travel") || @current_message.downcase.include?("trip")
      create_simple_travel_list
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

    # Extract any food items mentioned in the message
    mentioned_items = extract_grocery_items_from_message
    default_items = mentioned_items.any? ? mentioned_items : [ "Milk", "Bread", "Eggs" ]

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

  def create_simple_book_list
    list = @user.lists.create!(
      title: "Reading List",
      status: "active",
      list_type: "personal"
    )

    # Try to extract number of books requested
    quantity_match = @current_message.match(/(\d+)\s+books?/i)
    requested_count = quantity_match ? quantity_match[1].to_i : 5

    # Generate appropriate number of books
    book_titles = generate_fallback_books(requested_count)
    items_created = []

    book_titles.each_with_index do |book, index|
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

  def create_simple_travel_list
    list = @user.lists.create!(
      title: "Travel Planning",
      status: "active",
      list_type: "personal"
    )

    travel_tasks = [
      "Book transportation",
      "Reserve accommodation",
      "Plan itinerary",
      "Pack luggage",
      "Check travel documents"
    ]

    items_created = []
    travel_tasks.each_with_index do |task, index|
      item = list.list_items.create!(
        title: task,
        completed: false,
        priority: "medium",
        item_type: "task",
        position: index
      )
      items_created << item
    end

    {
      message: "Created travel planning list with #{items_created.count} tasks",
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

  # Helper methods for fallback creation
  def extract_grocery_items_from_message
    # Simple keyword extraction for grocery items
    food_keywords = %w[milk bread eggs cheese apples bananas yogurt chicken rice pasta]
    found_items = []

    food_keywords.each do |keyword|
      if @current_message.downcase.include?(keyword)
        found_items << keyword.capitalize
      end
    end

    found_items
  end

  def generate_fallback_books(count)
    all_books = [
      "Atomic Habits by James Clear",
      "Sapiens by Yuval Noah Harari",
      "The 7 Habits of Highly Effective People by Stephen Covey",
      "Mindset by Carol Dweck",
      "The Power of Now by Eckhart Tolle",
      "Thinking, Fast and Slow by Daniel Kahneman",
      "The Lean Startup by Eric Ries",
      "Deep Work by Cal Newport",
      "The Alchemist by Paulo Coelho",
      "Man's Search for Meaning by Viktor Frankl"
    ]

    # Return the requested number of books, cycling if necessary
    count = [ count, 10 ].min # Cap at 10 to avoid infinite arrays
    if count <= all_books.length
      all_books.first(count)
    else
      (all_books * ((count / all_books.length) + 1)).first(count)
    end
  end
end
