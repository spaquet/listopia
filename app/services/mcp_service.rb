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
    items.each_with_index do |item, index|
      list_item = list.list_items.create!(
        title: item,
        completed: false,  # ✅ Fixed: Use completed boolean instead of status
        priority: "medium",
        item_type: "shopping",  # ✅ Better type for grocery items
        position: index  # ✅ Fixed: Set unique position for each item
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
      planning_items.each_with_index do |item, index|
        list_item = sublist.list_items.create!(
          title: item,
          completed: false,  # ✅ Fixed: Use completed boolean instead of status
          priority: "medium",
          item_type: "task",
          position: index  # ✅ Fixed: Set unique position for each item
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
    items.each_with_index do |item, index|
      list_item = list.list_items.create!(
        title: item,
        completed: false,  # ✅ Fixed: Use completed boolean instead of status
        priority: "medium",
        item_type: "task",
        position: index  # ✅ Fixed: Set unique position for each item
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

  def create_book_list(message)
    lists_created = []
    items_created = []

    # Create book reading list
    list = @user.lists.create!(
      title: "Reading List",
      status: "active",
      list_type: "personal"
    )
    lists_created << list

    # Extract book titles from message
    books = extract_book_titles(message)
    books.each_with_index do |book, index|
      list_item = list.list_items.create!(
        title: book,
        completed: false,  # ✅ Fixed: Use completed boolean instead of status
        priority: "medium",
        item_type: "learning",  # ✅ Better type for reading
        position: index  # ✅ Fixed: Set unique position for each item
      )
      items_created << list_item
    end

    {
      message: "Created reading list with #{books.count} books: #{books.join(', ')}",
      lists_created: lists_created,
      items_created: items_created
    }
  end

  def create_travel_planning(message)
    lists_created = []
    items_created = []

    # Create travel planning list
    list = @user.lists.create!(
      title: "Travel Planning",
      status: "active",
      list_type: "personal"
    )
    lists_created << list

    # Add basic travel planning items
    travel_items = [
      "Research destinations",
      "Book flights",
      "Book accommodation",
      "Plan itinerary",
      "Check passport/visa requirements",
      "Pack luggage"
    ]

    travel_items.each_with_index do |item, index|
      list_item = list.list_items.create!(
        title: item,
        completed: false,  # ✅ Fixed: Use completed boolean instead of status
        priority: "medium",
        item_type: "travel",  # ✅ Better type for travel
        position: index  # ✅ Fixed: Set unique position for each item
      )
      items_created << list_item
    end

    {
      message: "Created travel planning list with #{travel_items.count} essential items",
      lists_created: lists_created,
      items_created: items_created
    }
  end

  # Extract methods for parsing user input

  def extract_grocery_items(message)
    # Simple extraction - in production this would use more sophisticated parsing
    default_items = [ "Milk", "Bread", "Eggs", "Fruits", "Vegetables" ]

    # Try to extract specific items from the message
    if message.include?("with") || message.include?(":")
      extracted = message.split(/with|:/).last&.split(/,|and/)&.map(&:strip)&.reject(&:blank?)
      return extracted if extracted&.any?
    end

    default_items
  end

  def extract_cities_from_message(message)
    # Simple city extraction - in production this would use NLP
    default_cities = [ "New York", "Los Angeles", "Chicago" ]

    # Look for city names in the message
    if message.downcase.include?("cities")
      # Try to extract specific cities mentioned
      words = message.split(/\s+/)
      cities = words.select { |w| w.match?(/^[A-Z][a-z]+$/) }.first(5)
      return cities if cities.any?
    end

    default_cities
  end

  def extract_book_titles(message)
    # Simple book extraction
    default_books = [ "To Kill a Mockingbird", "1984", "Pride and Prejudice" ]

    # Try to extract book titles from quotes or specific patterns
    titles = message.scan(/"([^"]+)"/).flatten
    return titles if titles.any?

    default_books
  end

  def extract_title_from_message(message)
    # Extract a meaningful title from the user's message
    words = message.split(/\s+/).reject { |w| common_word?(w) }
    words.first(3).join(" ").titleize || "New List"
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
    %w[the and or but with from that this they create make list].include?(word.downcase)
  end

  # Additional methods for AI-powered creation (future enhancement)

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
      plan["items"].each_with_index do |item_info, index|
        item_title = item_info.is_a?(Hash) ? item_info["title"] : item_info.to_s
        next if item_title.blank?

        item = list.list_items.create!(
          title: item_title,
          completed: false,  # ✅ Fixed: Use completed boolean instead of status
          priority: item_info.is_a?(Hash) ? (item_info["priority"] || "medium") : "medium",
          item_type: item_info.is_a?(Hash) ? (item_info["type"] || "task") : "task",
          position: index  # ✅ Fixed: Set unique position for each item
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
          list_type: plan["list_type"] || "personal"
        )
        lists_created << sublist

        # Add items to sublist
        if sublist_info.is_a?(Hash) && sublist_info["items"]&.any?
          sublist_info["items"].each_with_index do |item_info, index|
            item_title = item_info.is_a?(Hash) ? item_info["title"] : item_info.to_s
            next if item_title.blank?

            item = sublist.list_items.create!(
              title: item_title,
              completed: false,  # ✅ Fixed: Use completed boolean instead of status
              priority: item_info.is_a?(Hash) ? (item_info["priority"] || "medium") : "medium",
              item_type: item_info.is_a?(Hash) ? (item_info["type"] || "task") : "task",
              position: index  # ✅ Fixed: Set unique position for each item
            )
            items_created << item
          end
        end
      end
    end

    message = "Created '#{main_list.title}' with #{lists_created.count - 1} sublists and #{items_created.count} items"
    { lists: lists_created, items: items_created, message: message }
  end

  def create_simple_fallback(original_message)
    # Fallback to simple list creation if AI parsing fails
    create_general_list_with_items(original_message)
  end
end
