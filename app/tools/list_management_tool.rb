# app/tools/list_management_tool.rb

class ListManagementTool < RubyLLM::Tool
  description "Creates and manages lists of any type. Can create main lists with optional sub-lists, add items to existing lists, and view current lists"

  param :action, desc: "Action to perform: 'create_list' to create a new list, 'create_list_with_sublists' to create a main list with sub-lists, 'add_item' to add an item to an existing list, 'get_lists' to view existing lists"
  param :title, desc: "Title of the list or item", required: false
  param :description, desc: "Description of the list or item", required: false
  param :sub_lists, desc: "Comma-separated list of sub-list names (only for create_list_with_sublists)", required: false
  param :list_type, desc: "Type of list - personal or professional", required: false
  param :list_id, desc: "ID or title of existing list to add item to", required: false
  param :item_type, desc: "Type of item: task, goal, milestone, reminder, note, idea, etc.", required: false
  param :priority, desc: "Priority level: low, medium, high", required: false

  def initialize(user, context = {})
    @user = user
    @context = context
  end

  def execute(action:, title: nil, description: nil, sub_lists: nil, list_type: "personal", list_id: nil, item_type: "task", priority: "medium")
    case action.to_s
    when "create_list"
      create_simple_list(title: title, description: description, list_type: list_type)
    when "create_list_with_sublists"
      create_list_with_sublists(title: title, description: description, sub_lists: sub_lists, list_type: list_type)
    when "add_item"
      add_item_to_list(list_id: list_id, title: title, description: description, item_type: item_type, priority: priority)
    when "get_lists"
      get_user_lists
    else
      "Unknown action. Available actions: create_list, create_list_with_sublists, add_item, get_lists"
    end
  end

  private

  def create_simple_list(title:, description: nil, list_type: "personal")
    return "Title is required for creating a list" unless title

    list = @user.lists.create!(
      title: title,
      description: description,
      status: "active",
      list_type: list_type
    )

    broadcast_list_creation(list)

    "Created list '#{title}'"
  end

  def create_list_with_sublists(title:, description: nil, sub_lists: nil, list_type: "personal")
    return "Title is required for creating a list" unless title

    # Parse sub-lists data
    sub_lists_data = sub_lists.present? ? normalize_sub_lists_input(sub_lists) : []

    Rails.logger.info "Creating list with sublists: #{title}, sub_lists: #{sub_lists_data}"

    # Create the main list
    main_list = @user.lists.create!(
      title: title,
      description: description,
      status: "active",
      list_type: list_type
    )

    broadcast_list_creation(main_list)
    created_sub_lists = []

    # Create sub-lists if provided
    if sub_lists_data.present?
      Rails.logger.info "Creating sub-lists under main list ID: #{main_list.id}"

      sub_lists_data.each do |sub_list_name|
        sub_list = @user.lists.create!(
          title: sub_list_name.to_s,
          description: nil,
          status: "active",
          parent_list: main_list,
          list_type: list_type
        )

        broadcast_list_creation(sub_list)
        created_sub_lists << sub_list

        Rails.logger.info "Created sub-list: #{sub_list.title} with parent_list_id: #{sub_list.parent_list_id}"
      end

      # Reload the main list to ensure the sub_lists association is fresh
      main_list.reload
    end

    Rails.logger.info "Final result - Main list sub_lists count: #{main_list.sub_lists.count}"

    response = "Created list '#{main_list.title}'"
    if created_sub_lists.any?
      response += " with #{created_sub_lists.count} sub-lists: #{created_sub_lists.map(&:title).join(', ')}"
    end
    response
  end

  def add_item_to_list(list_id:, title:, description: nil, item_type: "task", priority: "medium")
    return "Both list_id and title are required for adding an item" unless list_id && title

    # Find the list by ID or title
    list = find_list(list_id)
    return "Could not find list with ID or title: #{list_id}" unless list

    # Create the item
    item = list.list_items.create!(
      title: title,
      description: description,
      position: list.list_items.count,
      item_type: item_type,
      priority: priority
    )

    broadcast_item_creation(list)

    "Added '#{title}' to list '#{list.title}'"
  end

  def get_user_lists
    lists = @user.lists.includes(:list_items, :sub_lists).recent.limit(20)

    if lists.empty?
      return "You don't have any lists yet."
    end

    response = "Your lists:\n"
    lists.each do |list|
      response += "- #{list.title} (#{list.list_items.count} items"
      response += ", #{list.sub_lists.count} sub-lists" if list.sub_lists.any?
      response += ")\n"

      # Show sub-lists
      if list.sub_lists.any?
        list.sub_lists.each do |sub_list|
          response += "  - #{sub_list.title} (#{sub_list.list_items.count} items)\n"
        end
      end
    end
    response
  end

  def normalize_sub_lists_input(input)
    return [] if input.nil? || input.empty?

    case input
    when String
      # Handle comma-separated string
      input.split(",").map(&:strip).reject(&:empty?)
    when Array
      input
    else
      []
    end
  end

  def determine_planning_list_type(title, planning_context)
    # Simple heuristic - if it sounds business-related, make it professional
    business_keywords = [ "work", "business", "project", "meeting", "client", "company", "team", "professional", "corporate" ]

    content_to_check = "#{title} #{planning_context}".downcase

    if business_keywords.any? { |keyword| content_to_check.include?(keyword) }
      "professional"
    else
      "personal"
    end
  end

  def find_list(list_id)
    return nil if list_id.nil? || list_id.empty?

    # Handle special case for "most_recent"
    return @user.lists.order(:updated_at).last if list_id == "most_recent"

    # Try to find by UUID first
    if list_id.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
      @user.lists.find_by(id: list_id)
    else
      # Find by title (partial match)
      @user.lists.find_by("title ILIKE ?", "%#{list_id}%")
    end
  end

  def broadcast_list_creation(list)
    affected_users = [ list.owner ]
    affected_users.concat(list.collaborators) if list.collaborators.any?

    affected_users.uniq.each do |user|
      begin
        # Prepend new list card to lists grid (if user is on lists index)
        Turbo::StreamsChannel.broadcast_prepend_to(
          "user_lists_#{user.id}",
          target: "lists-grid",
          partial: "lists/list_card",
          locals: { list: list, current_user: user }
        )

        # Remove empty state if this might be the first list
        Turbo::StreamsChannel.broadcast_remove_to(
          "user_lists_#{user.id}",
          target: "empty-state"
        )
      rescue => e
        Rails.logger.error "Failed to broadcast list creation for user #{user.id}: #{e.message}"
      end
    end
  end

  def broadcast_item_creation(list)
    # Simple broadcast for item creation
    affected_users = [ list.owner ]
    affected_users.concat(list.collaborators) if list.collaborators.any?

    affected_users.uniq.each do |user|
      begin
        # Update list card to reflect new item count
        Turbo::StreamsChannel.broadcast_replace_to(
          "user_lists_#{user.id}",
          target: "list_card_#{list.id}",
          partial: "lists/list_card",
          locals: { list: list, current_user: user }
        )
      rescue => e
        Rails.logger.error "Failed to broadcast item creation for user #{user.id}: #{e.message}"
      end
    end
  end

  private

  def add_context_specific_items(list, planning_context, location = nil)
    # Don't add predefined items - let the AI decide what items are needed
    # through additional tool calls or user interaction
    Rails.logger.info "Created sub-list '#{list.title}' - ready for AI to populate with relevant items"
  end

  def add_planning_overview_items(list, planning_context)
    # Add only generic high-level planning items that apply to any project
    overview_items = [
      "Define objectives and success criteria",
      "Create timeline and milestones",
      "Identify resources and requirements",
      "Plan execution strategy",
      "Monitor progress and adjust as needed"
    ]

    overview_items.each_with_index do |item_title, index|
      list.list_items.create!(
        title: item_title,
        position: index,
        item_type: "milestone",
        priority: "high"
      )
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

  def broadcast_list_creation(list)
    affected_users = [ list.owner ]
    affected_users.concat(list.collaborators) if list.collaborators.any?

    affected_users.uniq.each do |user|
      begin
        # Prepend new list card to lists grid (if user is on lists index)
        Turbo::StreamsChannel.broadcast_prepend_to(
          "user_lists_#{user.id}",
          target: "lists-grid",
          partial: "lists/list_card",
          locals: { list: list, current_user: user }
        )

        # Remove empty state if this might be the first list
        Turbo::StreamsChannel.broadcast_remove_to(
          "user_lists_#{user.id}",
          target: "empty-state"
        )
      rescue => e
        Rails.logger.error "Failed to broadcast list creation for user #{user.id}: #{e.message}"
      end
    end
  end
end
