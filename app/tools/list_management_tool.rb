# app/tools/list_management_tool.rb
class ListManagementTool < RubyLLM::Tool
  description "Manages lists and list items in Listopia. Use this tool for ANY planning, organization, or task management needs. You can create main lists, sub-lists, and organize complex projects intelligently."

  # RubyLLM 1.8+ compatible parameter definitions (no enum keyword)
  param :action, desc: "Action to perform: create_list, create_sub_lists, add_item, get_lists, get_list_items, complete_item, create_planning_list"
  param :title, desc: "Title for new lists or items", required: false
  param :description, desc: "Description for new lists or items", required: false
  param :list_id, desc: "ID or title reference to existing list", required: false
  param :item_id, desc: "ID of the item to modify", required: false
  param :parent_list_id, desc: "Parent list ID when creating sub-lists", required: false
  param :sub_lists, desc: "Array of sub-list data or comma-separated string of cities/names when creating multiple lists", required: false
  param :planning_context, desc: "Context for planning (roadshow, conference, project, etc.)", required: false
  param :list_type, desc: "Type of list: personal or professional", required: false

  def initialize(user, context = {})
    @user = user
    @context = context
  end

  def execute(action:, **params)
    case action
    when "create_list"
      create_list(params[:title], params[:description], params[:list_type])
    when "create_sub_lists"
      create_sub_lists(params[:parent_list_id], params[:sub_lists])
    when "add_item"
      add_item(params[:list_id], params[:title], params[:description])
    when "get_lists"
      get_lists
    when "get_list_items"
      get_list_items(params[:list_id])
    when "complete_item"
      complete_item(params[:item_id])
    when "create_planning_list"
      create_planning_list(params[:title], params[:planning_context], params[:sub_lists])
    else
      { success: false, error: "Unknown action: #{action}" }
    end
  end

  private

  def create_list(title, description = nil, list_type = nil)
    # Determine list type from context or title
    determined_type = determine_list_type(title, description, list_type)

    list = @user.lists.create!(
      title: title,
      description: description,
      status: "active",
      list_type: determined_type
    )

    broadcast_list_creation(list)

    {
      success: true,
      message: "Created #{determined_type} list '#{title}'",
      list: serialize_list(list)
    }
  end

  # NEW: Create a planning list with main list and sub-lists using the new database structure
  def create_planning_list(title, planning_context, sub_lists_data = nil)
    # Determine if this is professional or personal based on context
    list_type = determine_planning_list_type(title, planning_context)

    # Create main planning list
    main_list = @user.lists.create!(
      title: title,
      description: "Main planning list for #{planning_context}",
      status: "active",
      list_type: list_type
    )

    # Add planning overview items to main list
    add_planning_overview_items(main_list, planning_context)

    created_lists = [ main_list ]
    broadcast_list_creation(main_list)

    # Create sub-lists if provided, using the new parent_list relationship
    if sub_lists_data.present?
      sub_lists_result = create_sub_lists(main_list.id, sub_lists_data)
      if sub_lists_result[:success]
        # Reload the main list to get the updated sub_lists association
        main_list.reload
        created_lists.concat(main_list.sub_lists.to_a)
      end
    end

    {
      success: true,
      message: "Created #{list_type} planning structure for #{planning_context} with #{main_list.sub_lists.count} sub-lists",
      main_list: serialize_list(main_list),
      sub_lists: main_list.sub_lists.map { |l| serialize_list(l) },
      total_lists_created: created_lists.length
    }
  end

  def create_sub_lists(parent_list_id, sub_lists_data)
    parent_list = find_list(parent_list_id) if parent_list_id && parent_list_id != "most_recent"

    # Handle different input formats for sub_lists_data
    sub_lists_array = normalize_sub_lists_input(sub_lists_data)

    return { success: false, error: "No sub-lists data provided" } if sub_lists_array.empty?

    created_lists = []

    sub_lists_array.each do |sub_list_info|
      # Handle both hash format and string format
      if sub_list_info.is_a?(String)
        # For roadshow cities, create default planning items
        list_title = "#{sub_list_info} - Roadshow Planning"
        list_description = "Planning checklist for #{sub_list_info} roadshow stop"

        # USE NEW DATABASE STRUCTURE: Set parent_list relationship
        list = @user.lists.create!(
          title: list_title,
          description: list_description,
          status: "active",
          parent_list: parent_list,  # Use the new parent_list association
          list_type: parent_list&.list_type || "professional" # Inherit from parent or default to professional
        )

        # Add default roadshow planning items
        default_roadshow_items = [
          "Venue research and booking",
          "Local partnership outreach",
          "Marketing and promotion planning",
          "Travel and accommodation arrangements",
          "Equipment and materials shipping",
          "Local team coordination",
          "Post-event follow-up planning"
        ]

        default_roadshow_items.each_with_index do |item_title, index|
          list.list_items.create!(
            title: item_title,
            position: index,
            item_type: "task",
            priority: "medium"
          )
        end
      else
        # Handle hash format
        list = @user.lists.create!(
          title: sub_list_info[:title] || sub_list_info["title"],
          description: sub_list_info[:description] || sub_list_info["description"],
          status: "active",
          parent_list: parent_list,  # Use the new parent_list association
          list_type: parent_list&.list_type || "personal"
        )

        # Add items to sub-list if provided
        if sub_list_info[:items] || sub_list_info["items"]
          items_data = sub_list_info[:items] || sub_list_info["items"]
          items_data.each_with_index do |item_data, index|
            list.list_items.create!(
              title: item_data[:title] || item_data["title"] || item_data,
              description: item_data[:description] || item_data["description"],
              position: index,
              item_type: "task",
              priority: "medium"
            )
          end
        end
      end

      broadcast_list_creation(list)
      created_lists << serialize_list(list)
    end

    {
      success: true,
      message: "Created #{created_lists.length} sub-lists#{parent_list ? " under '#{parent_list.title}'" : ""}",
      lists: created_lists,
      parent_list: parent_list ? serialize_list(parent_list) : nil
    }
  end

  def add_planning_overview_items(list, planning_context)
    case planning_context.to_s.downcase
    when "roadshow", "roadshow planning"
      overview_items = [
        "Define roadshow objectives and success metrics",
        "Identify target cities and venues",
        "Create master timeline and schedule",
        "Budget planning and approval",
        "Team roles and responsibilities assignment",
        "Marketing and communication strategy",
        "Post-roadshow analysis and follow-up plan"
      ]
    when "conference", "event"
      overview_items = [
        "Define conference goals and objectives",
        "Venue selection and booking",
        "Speaker recruitment and management",
        "Registration and ticketing setup",
        "Marketing and promotion campaign",
        "Logistics and day-of coordination",
        "Post-event follow-up and analysis"
      ]
    else
      overview_items = [
        "Project planning and scope definition",
        "Timeline and milestone planning",
        "Resource allocation and budgeting",
        "Team coordination and communication",
        "Risk assessment and mitigation",
        "Progress tracking and reporting"
      ]
    end

    overview_items.each_with_index do |item_title, index|
      list.list_items.create!(
        title: item_title,
        position: index,
        item_type: "milestone",
        priority: "high"
      )
    end
  end

  def determine_list_type(title, description, explicit_type)
    return explicit_type if explicit_type.present?

    # Business/professional keywords
    professional_keywords = [
      "roadshow", "conference", "business", "work", "project", "meeting",
      "client", "sales", "marketing", "team", "professional", "corporate",
      "company", "enterprise", "strategy", "planning", "budget", "revenue"
    ]

    content_to_check = "#{title} #{description}".downcase

    if professional_keywords.any? { |keyword| content_to_check.include?(keyword) }
      "professional"
    else
      "personal" # Default
    end
  end

  def determine_planning_list_type(title, planning_context)
    business_contexts = [ "roadshow", "conference", "business", "work", "professional", "corporate" ]

    context_check = "#{title} #{planning_context}".downcase

    if business_contexts.any? { |keyword| context_check.include?(keyword) }
      "professional"
    else
      "personal"
    end
  end

  def normalize_sub_lists_input(input)
    return [] if input.nil? || input.empty?

    case input
    when String
      # Handle comma-separated string like "San Francisco, New York, Austin"
      input.split(",").map(&:strip).reject(&:empty?)
    when Array
      input
    else
      []
    end
  end

  def add_item(list_id, title, description = nil)
    list = find_list(list_id)
    return { success: false, error: "List not found" } unless list

    item = list.list_items.create!(
      title: title,
      description: description,
      position: list.list_items.count,
      item_type: "task",
      priority: "medium"
    )

    broadcast_item_update(item)

    {
      success: true,
      message: "Added '#{title}' to '#{list.title}'",
      item: serialize_item(item)
    }
  end

  def get_lists
    lists = @user.lists.includes(:list_items, :sub_lists).recent.limit(20)

    {
      success: true,
      lists: lists.map { |list| serialize_list(list) },
      total_count: @user.lists.count
    }
  end

  def get_list_items(list_id)
    list = find_list(list_id)
    return { success: false, error: "List not found" } unless list

    items = list.list_items.order(:position)

    {
      success: true,
      list: serialize_list(list),
      items: items.map { |item| serialize_item(item) }
    }
  end

  def complete_item(item_id)
    # Find item across all user's lists
    item = @user.lists.joins(:list_items).find_by(list_items: { id: item_id })&.list_items&.find(item_id)
    return { success: false, error: "Item not found" } unless item

    item.update!(completed: true, completed_at: Time.current)
    broadcast_item_update(item)

    {
      success: true,
      message: "Marked '#{item.title}' as completed",
      item: serialize_item(item)
    }
  end

  def find_list(list_id)
    return nil if list_id.nil? || list_id.empty?

    # Handle special case for "most_recent"
    return @user.lists.order(:updated_at).last if list_id == "most_recent"

    if list_id.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
      @user.lists.find_by(id: list_id)
    else
      @user.lists.find_by("title ILIKE ?", "%#{list_id}%")
    end
  end

  def serialize_list(list)
    {
      id: list.id,
      title: list.title,
      description: list.description,
      status: list.status,
      list_type: list.list_type,
      items_count: list.list_items.count,
      parent_list_id: list.parent_list_id,  # Include parent relationship
      sub_lists_count: list.respond_to?(:sub_lists) ? list.sub_lists.count : 0,  # Include sub-list count
      created_at: list.created_at,
      updated_at: list.updated_at
    }
  end

  def serialize_item(item)
    {
      id: item.id,
      title: item.title,
      description: item.description,
      completed: item.completed,
      item_type: item.item_type,
      priority: item.priority,
      position: item.position,
      list_id: item.list_id,
      created_at: item.created_at,
      updated_at: item.updated_at
    }
  end

  # FIXED: Use correct Turbo Stream broadcast targets
  def broadcast_list_creation(list)
    Turbo::StreamsChannel.broadcast_prepend_to(
      "user_lists_#{@user.id}",  # Fixed target name to match existing patterns
      target: "lists-grid",
      partial: "lists/list_card",
      locals: { list: list, current_user: @user }
    )

    # Remove empty state if this might be the first list
    Turbo::StreamsChannel.broadcast_remove_to(
      "user_lists_#{@user.id}",
      target: "empty-state"
    )
  rescue => e
    Rails.logger.error "Failed to broadcast list creation: #{e.message}"
    # Don't let broadcast errors break the main functionality
  end

  def broadcast_item_update(item)
    # Turbo Stream broadcasts for real-time updates
    Turbo::StreamsChannel.broadcast_replace_to(
      "user_#{@user.id}_list_#{item.list_id}",
      target: "list_items",
      partial: "list_items/item_cards",
      locals: { items: item.list.list_items.order(:position) }
    )
  rescue => e
    Rails.logger.error "Failed to broadcast item update: #{e.message}"
    # Don't let broadcast errors break the main functionality
  end
end
