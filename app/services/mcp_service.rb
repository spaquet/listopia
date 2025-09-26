# app/services/mcp_service.rb
class McpService
  def initialize(user:, context: {})
    @user = user
    @context = context
    @chat = find_or_create_chat
  end

  def process_message(message_content)
    # Use AI to understand and create lists with items
    result = ai_powered_list_creation(message_content)

    # Create response message
    response_message = @chat.add_message(
      role: "assistant",
      content: result[:message],
      message_type: "text"
    )

    # Return both message and created lists for UI updates
    {
      message: response_message,
      lists_created: result[:lists_created],
      items_created: result[:items_created]
    }
  rescue => e
    Rails.logger.error "McpService error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")

    error_message = @chat.add_message(
      role: "assistant",
      content: "I encountered an error creating your lists. Please try again.",
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

  def ai_powered_list_creation(user_message)
    # For now, use simple pattern matching until we can set up proper AI analysis
    # This will work immediately and we can enhance it later

    if simple_grocery_request?(user_message)
      create_grocery_list_with_items(user_message)
    elsif roadshow_request?(user_message)
      create_roadshow_with_cities(user_message)
    elsif book_request?(user_message)
      create_book_list(user_message)
    elsif travel_request?(user_message)
      create_travel_planning(user_message)
    else
      create_general_list_with_items(user_message)
    end
  end

  def simple_grocery_request?(message)
    message.downcase.include?("grocery") && message.downcase.include?("list")
  end

  def roadshow_request?(message)
    message.downcase.include?("roadshow") ||
    (message.downcase.include?("cities") && message.downcase.include?("organize"))
  end

  def book_request?(message)
    message.downcase.include?("book") && message.downcase.include?("list")
  end

  def travel_request?(message)
    message.downcase.include?("travel") || message.downcase.include?("vacation") ||
    message.downcase.include?("trip")
  end

  def create_grocery_list_with_items(message)
    lists_created = []
    items_created = []

    # Create grocery list
    list = @user.lists.create!(
      title: "Grocery List",
      status: "active",
      list_type: "personal"
    )
    lists_created << list

    # Extract items from message
    items = extract_grocery_items(message)
    items.each do |item|
      list_item = list.list_items.create!(
        title: item,
        status: "pending",
        priority: "medium",
        item_type: "task"
      )
      items_created << list_item
    end

    {
      message: "Created grocery list with #{items.count} items: #{items.join(', ')}",
      lists_created: lists_created,
      items_created: items_created
    }
  end

  def create_roadshow_with_cities(message)
    lists_created = []
    items_created = []

    # Create main list
    main_list = @user.lists.create!(
      title: "Roadshow Planning",
      status: "active",
      list_type: "professional"
    )
    lists_created << main_list

    # Extract cities
    cities = extract_cities_from_message(message)
    cities.each do |city|
      sublist = @user.lists.create!(
        title: "#{city} Stop",
        parent_list: main_list,
        status: "active",
        list_type: "professional"
      )
      lists_created << sublist

      # Add basic planning items to each city
      planning_items = [ "Book venue", "Arrange travel", "Local marketing", "Setup logistics" ]
      planning_items.each do |item|
        list_item = sublist.list_items.create!(
          title: item,
          status: "pending",
          priority: "medium",
          item_type: "task"
        )
        items_created << list_item
      end
    end

    {
      message: "Created roadshow planning with #{cities.count} city stops: #{cities.join(', ')}",
      lists_created: lists_created,
      items_created: items_created
    }
  end

  def create_general_list_with_items(message)
    lists_created = []
    items_created = []

    # Extract title
    title = extract_title_from_message(message)

    list = @user.lists.create!(
      title: title,
      status: "active",
      list_type: "personal"
    )
    lists_created << list

    # Try to extract any items mentioned
    items = extract_items_from_message(message)
    items.each do |item|
      list_item = list.list_items.create!(
        title: item,
        status: "pending",
        priority: "medium",
        item_type: "task"
      )
      items_created << list_item
    end

    message_text = if items.any?
                     "Created '#{title}' with #{items.count} items"
    else
                     "Created '#{title}' - ready for you to add items"
    end

    {
      message: message_text,
      lists_created: lists_created,
      items_created: items_created
    }
  end

  def extract_grocery_items(message)
    # Look for specific grocery items
    items = []

    # Pattern for quantities + items (2 apples, 1 bottle of water)
    quantity_items = message.scan(/(\d+\s+[^,\.!?]+)/i)
    items.concat(quantity_items.flatten.map(&:strip))

    # Common grocery words
    grocery_words = %w[milk chocolate bread eggs butter cheese apples bananas chicken beef]
    grocery_words.each do |word|
      if message.downcase.include?(word)
        items << word.capitalize
      end
    end

    # Clean up
    items.uniq.map(&:strip).reject(&:empty?)
  end

  def extract_cities_from_message(message)
    # Look for known city names
    known_cities = [ "San Francisco", "New York", "Austin", "Denver", "Seattle", "Portland", "Boston", "Los Angeles" ]
    cities = known_cities.select { |city| message.include?(city) }

    # If no cities found in this message, return the full list
    cities.any? ? cities : known_cities
  end

  def extract_title_from_message(message)
    # Simple title extraction
    words = message.split(/\s+/).select { |w| w.length > 3 && !common_word?(w) }
    words.first(2).join(" ").titleize || "New List"
  end

  def extract_items_from_message(message)
    # Look for comma-separated items
    if match = message.match(/with\s+([^\.!?]+)/i)
      items_text = match[1]
      items = items_text.split(/,|\sand\s/).map(&:strip)
      items.select { |item| item.length > 2 }
    else
      []
    end
  end

  def common_word?(word)
    %w[the and or but with from that this they].include?(word.downcase)
  end

  def execute_list_creation_plan(ai_response, original_message)
    begin
      # Parse AI response
      plan = JSON.parse(ai_response)

      lists_created = []
      items_created = []

      if plan["structure_type"] == "single"
        result = create_single_list_from_plan(plan)
        lists_created = result[:lists]
        items_created = result[:items]
        message = result[:message]
      else # hierarchical
        result = create_hierarchical_from_plan(plan)
        lists_created = result[:lists]
        items_created = result[:items]
        message = result[:message]
      end

      {
        message: message,
        lists_created: lists_created,
        items_created: items_created
      }
    rescue JSON::ParserError => e
      Rails.logger.error "JSON parse error: #{e.message}"
      Rails.logger.error "AI Response: #{ai_response}"
      create_simple_fallback(original_message)
    end
  end

  def create_single_list_from_plan(plan)
    lists_created = []
    items_created = []

    # Create the main list
    list = @user.lists.create!(
      title: plan["title"] || "New List",
      status: "active",
      list_type: plan["list_type"] || "personal"
    )
    lists_created << list

    # Add items to the list
    if plan["items"]&.any?
      plan["items"].each do |item_info|
        item_title = item_info.is_a?(Hash) ? item_info["title"] : item_info.to_s
        next if item_title.blank?

        item = list.list_items.create!(
          title: item_title,
          status: "pending",
          priority: item_info.is_a?(Hash) ? (item_info["priority"] || "medium") : "medium",
          item_type: item_info.is_a?(Hash) ? (item_info["type"] || "task") : "task"
        )
        items_created << item
      end
    end

    message = if items_created.any?
                "Created '#{list.title}' with #{items_created.count} items"
    else
                "Created '#{list.title}' - ready for you to add items"
    end

    { lists: lists_created, items: items_created, message: message }
  end

  def create_hierarchical_from_plan(plan)
    lists_created = []
    items_created = []

    # Create main list
    main_list = @user.lists.create!(
      title: plan["title"] || "Planning List",
      status: "active",
      list_type: plan["list_type"] || "personal"
    )
    lists_created << main_list

    # Create sublists
    if plan["sublists"]&.any?
      plan["sublists"].each do |sublist_info|
        sublist_title = sublist_info.is_a?(Hash) ? sublist_info["title"] : sublist_info.to_s
        next if sublist_title.blank?

        sublist = @user.lists.create!(
          title: sublist_title,
          parent_list: main_list,
          status: "active",
          list_type: main_list.list_type
        )
        lists_created << sublist

        # Add items to sublists if specified
        if sublist_info.is_a?(Hash) && sublist_info["items"]&.any?
          sublist_info["items"].each do |item_info|
            item_title = item_info.is_a?(Hash) ? item_info["title"] : item_info.to_s
            next if item_title.blank?

            item = sublist.list_items.create!(
              title: item_title,
              status: "pending",
              priority: item_info.is_a?(Hash) ? (item_info["priority"] || "medium") : "medium",
              item_type: item_info.is_a?(Hash) ? (item_info["type"] || "task") : "task"
            )
            items_created << item
          end
        end
      end
    end

    sublists_names = lists_created[1..-1]&.map(&:title) || []
    message = "Created '#{main_list.title}' with #{sublists_names.count} sections: #{sublists_names.join(', ')}"

    { lists: lists_created, items: items_created, message: message }
  end

  def create_simple_fallback(message)
    # Extract basic title
    title = message.split(/\s+/).select { |w| w.length > 3 }.first(2).join(" ").titleize
    title = "New List" if title.blank?

    list = @user.lists.create!(
      title: title,
      status: "active",
      list_type: "personal"
    )

    {
      message: "Created '#{title}' - what would you like to add?",
      lists_created: [ list ],
      items_created: []
    }
  end

  def build_analysis_prompt(user_message)
    <<~PROMPT
      Analyze this user request and create a plan for organizing their lists and tasks: "#{user_message}"

      Rules:
      1. Determine if this needs a single list or main list with sublists (max 1 level deep)
      2. Extract specific items/tasks they mentioned
      3. Create actionable items that help them achieve their goal
      4. Determine if this is personal or professional context

      Respond with JSON only:
      {
        "structure_type": "single" or "hierarchical",
        "title": "Main List Title",
        "list_type": "personal" or "professional",
        "items": ["item1", "item2"] (for single lists),
        "sublists": [
          {
            "title": "Sublist Name",
            "items": ["task1", "task2"]
          }
        ] (for hierarchical)
      }

      Examples:
      - "grocery list with apples, milk" → single list with those items
      - "plan vacation to Paris" → hierarchical: Planning/Packing/Bookings sublists with relevant tasks
      - "organize team 1:1s" → hierarchical: sublists for each team member with meeting prep tasks
      - "booklist to develop my mind" → single list ready for book titles

      Always populate with actionable items that help the user accomplish their goal.
    PROMPT
  end

  def default_model
    Model.find_by(provider: "openai") || Model.first
  end
end
