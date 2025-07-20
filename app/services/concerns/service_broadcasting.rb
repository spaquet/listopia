# app/services/concerns/service_broadcasting.rb
module ServiceBroadcasting
  extend ActiveSupport::Concern

  private

  # Context-aware broadcasting that works from both controllers and services
  # Use skip_broadcasts: true to prevent broadcasting during intermediate steps
  def broadcast_all_updates(list, skip_broadcasts: false)
    return if skip_broadcasts

    broadcast_dashboard_updates(list)
    broadcast_lists_index_updates(list)
  end

  # Update dashboard for all affected users (service-safe version)
  def broadcast_dashboard_updates(list)
    # Get all affected users efficiently
    affected_users = [list.owner]

    # Only load collaborators if list has any (avoid N+1)
    if list.list_collaborations_count > 0
      affected_users.concat(list.collaborators.to_a)
    end

    affected_users.uniq.each do |user|
      begin
        user_data = dashboard_data_for_user(user)

        # Broadcast stats update
        Turbo::StreamsChannel.broadcast_replace_to(
          "user_dashboard_#{user.id}",
          target: "dashboard-stats",
          partial: "dashboard/stats_overview",
          locals: { stats: user_data[:stats] }
        )

        # Broadcast appropriate lists section based on relationship to list
        if user.id == list.owner.id
          # Update owner's "my lists" section
          Turbo::StreamsChannel.broadcast_replace_to(
            "user_dashboard_#{user.id}",
            target: "dashboard-my-lists",
            partial: "dashboard/my_lists",
            locals: { lists: user_data[:my_lists] }
          )
        else
          # Update collaborator's "collaborated lists" section
          Turbo::StreamsChannel.broadcast_replace_to(
            "user_dashboard_#{user.id}",
            target: "dashboard-collaborated-lists",
            partial: "dashboard/collaborated_lists",
            locals: { lists: user_data[:collaborated_lists] }
          )
        end

        # Update recent activity for all affected users
        Turbo::StreamsChannel.broadcast_replace_to(
          "user_dashboard_#{user.id}",
          target: "dashboard-recent-activity",
          partial: "dashboard/recent_activity",
          locals: { items: user_data[:recent_items] }
        )
      rescue => e
        # Log error but don't fail the entire operation
        Rails.logger.error "Failed to broadcast dashboard update for user #{user.id}: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
      end
    end
  end

  # Update lists index for all affected users (service-safe version)
  def broadcast_lists_index_updates(list)
    affected_users = [list.owner]

    if list.list_collaborations_count > 0
      affected_users.concat(list.collaborators.to_a)
    end

    affected_users.uniq.each do |user|
      begin
        # For newly created lists, use a more reliable approach
        if list.created_at > 1.minute.ago
          # Only broadcast if the list exists and is accessible
          if user.accessible_lists.exists?(list.id)
            # Use prepend instead of replace to add the new list at the top
            Turbo::StreamsChannel.broadcast_prepend_to(
              "user_lists_#{user.id}",
              target: "lists-container",
              partial: "lists/list_card",
              locals: { list: list }
            )
          end
        else
          # For existing lists, do a full refresh of the lists container
          user_lists = user.accessible_lists.order(updated_at: :desc)

          # Only broadcast if the user is currently on the lists page
          # We can check this by looking for the stream identifier in active connections
          Turbo::StreamsChannel.broadcast_replace_to(
            "user_lists_#{user.id}",
            target: "lists-grid-only", # Target the inner grid, not the entire container
            partial: "lists/lists_grid",
            locals: { lists: user_lists }
          )
        end
      rescue => e
        # Log error but don't fail the entire operation
        Rails.logger.error "Failed to broadcast lists index update for user #{user.id}: #{e.message}"
        Rails.logger.error e.backtrace.join("\n")
      end
    end
  end

  # Service-safe method to get dashboard data without view_context
  # Optimized to avoid N+1 queries
  def dashboard_data_for_user(user)
    # Get accessible list IDs efficiently
    accessible_list_ids = user.accessible_lists.pluck(:id)

    {
      stats: calculate_dashboard_stats_for_user(user, accessible_list_ids),
      my_lists: user.lists.order(updated_at: :desc).limit(10),
      collaborated_lists: user.collaborated_lists.includes(:owner).order(updated_at: :desc).limit(10),
      recent_items: ListItem.joins(:list)
                           .where(list_id: accessible_list_ids)
                           .includes(:list)
                           .order(created_at: :desc)
                           .limit(10)
    }
  end

  # Calculate statistics efficiently without N+1 queries
  def calculate_dashboard_stats_for_user(user, accessible_list_ids = nil)
    accessible_list_ids ||= user.accessible_lists.pluck(:id)
    accessible_lists = List.where(id: accessible_list_ids)

    {
      total_lists: accessible_lists.count,
      active_lists: accessible_lists.where(status: :active).count,
      completed_lists: accessible_lists.where(status: :completed).count,
      total_items: ListItem.where(list_id: accessible_list_ids).count,
      completed_items: ListItem.where(list_id: accessible_list_ids, completed: true).count,
      overdue_items: ListItem.where(list_id: accessible_list_ids)
                            .where("due_date < ? AND completed = false", Date.current).count
    }
  end
end

# app/services/list_creation_service.rb
class ListCreationService
  include ServiceBroadcasting  # Use service-safe broadcasting instead

  attr_reader :user, :list, :errors

  def initialize(user)
    @user = user
    @errors = []
  end

  # Create a regular list
  def create_list(title:, description: nil, skip_broadcasts: false, **options)
    @list = @user.lists.build(
      title: title,
      description: description,
      status: options[:status] || :active,
      **options.slice(:is_public, :list_type, :color_theme)
    )

    if @list.save
      # Only broadcast if not explicitly skipped (prevents double broadcasting)
      broadcast_all_updates(@list, skip_broadcasts: skip_broadcasts) unless skip_broadcasts
      Result.success(@list)
    else
      @errors = @list.errors.full_messages
      Result.failure(@errors)
    end
  end

  # Create a planning list with auto-generated items
  def create_planning_list(title:, description: nil, planning_context: nil, **options)
    ActiveRecord::Base.transaction do
      # Create the list first WITHOUT broadcasting (to avoid duplication)
      result = create_list(title: title, description: description, skip_broadcasts: true, **options)
      return result unless result.success?

      # Add planning items if context provided
      if planning_context.present?
        items_service = ListItemService.new(@list, @user)
        suggested_items = generate_planning_items(planning_context, title)

        suggested_items.each_with_index do |item_data, index|
          # Create items without broadcasting (to avoid multiple broadcasts)
          item_result = items_service.create_item(
            title: item_data[:title],
            description: item_data[:description],
            item_type: item_data[:type] || "task",
            priority: item_data[:priority] || "medium",
            position: index,
            skip_broadcasts: true
          )

          unless item_result.success?
            raise ActiveRecord::Rollback, "Failed to create planning items"
          end
        end
      end

      # Single broadcast after everything is complete
      broadcast_all_updates(@list)
      Result.success(@list)
    end
  rescue => e
    @errors = [ e.message ]
    Result.failure(@errors)
  end

  # Duplicate an existing list
  def duplicate_list(source_list, new_title: nil)
    new_title ||= "Copy of #{source_list.title}"

    ActiveRecord::Base.transaction do
      # Create the new list
      result = create_list(
        title: new_title,
        description: source_list.description,
        status: :active, # Always start duplicates as active
        list_type: source_list.list_type,
        color_theme: source_list.color_theme
      )

      return result unless result.success?

      # Copy all items from source list
      source_list.list_items.order(:position).each_with_index do |source_item, index|
        items_service = ListItemService.new(@list, @user)
        item_result = items_service.create_item(
          title: source_item.title,
          description: source_item.description,
          item_type: source_item.item_type,
          priority: source_item.priority,
          position: index,
          due_date: source_item.due_date,
          url: source_item.url,
          metadata: source_item.metadata
        )

        unless item_result.success?
          raise ActiveRecord::Rollback, "Failed to duplicate items"
        end
      end

      # Broadcast final state
      broadcast_all_updates(@list)
      Result.success(@list)
    end
  rescue => e
    @errors = [ e.message ]
    Result.failure(@errors)
  end

  private

  # Conference planning items
  def generate_planning_items(context, title)
    case context.downcase
    when "conference"
      generate_conference_items(title)
    when "vacation", "travel"
      generate_vacation_items(title)
    when "project"
      generate_project_items(title)
    when "goals"
      generate_goals_items(title)
    when "shopping"
      generate_shopping_items(title)
    when "wedding"
      generate_wedding_items(title)
    when "moving", "relocation"
      generate_moving_items(title)
    else
      generate_generic_planning_items(title, context)
    end
  end

  def generate_conference_items(title)
    [
      { title: "Set conference dates and duration", description: "Choose dates avoiding conflicts with holidays and other major events", type: "milestone", priority: "high" },
      { title: "Research and book venue", description: "Find venue with adequate capacity, AV equipment, and catering facilities", type: "task", priority: "high" },
      { title: "Create speaker lineup and invite keynotes", description: "Identify and reach out to industry experts and thought leaders", type: "task", priority: "high" },
      { title: "Set up registration system", description: "Configure online registration with payment processing and attendee management", type: "task", priority: "medium" },
      { title: "Plan conference schedule and sessions", description: "Create detailed agenda with session tracks and break times", type: "task", priority: "medium" },
      { title: "Arrange catering and refreshments", description: "Coordinate meals, coffee breaks, and dietary requirements", type: "task", priority: "medium" },
      { title: "Design marketing materials and website", description: "Create branding, promotional content, and conference website", type: "task", priority: "medium" },
      { title: "Coordinate accommodation for speakers", description: "Book hotels and arrange transportation for out-of-town speakers", type: "task", priority: "low" },
      { title: "Prepare conference swag and materials", description: "Order badges, lanyards, welcome bags, and branded items", type: "task", priority: "low" },
      { title: "Set up live streaming and recording", description: "Arrange technical setup for remote attendees and session recordings", type: "task", priority: "medium" },
      { title: "Plan networking activities", description: "Organize evening events, mixers, and networking opportunities", type: "task", priority: "low" },
      { title: "Finalize sponsorship packages", description: "Secure sponsors and prepare sponsor recognition materials", type: "task", priority: "medium" }
    ]
  end

  def generate_vacation_items(title)
    [
      { title: "Research destination and attractions", description: "Explore must-see places and local experiences", type: "research", priority: "high" },
      { title: "Book flights", description: "Compare prices and book airline tickets", type: "booking", priority: "high" },
      { title: "Reserve accommodation", description: "Book hotel, vacation rental, or other lodging", type: "booking", priority: "high" },
      { title: "Plan daily itinerary", description: "Create day-by-day schedule of activities", type: "task", priority: "medium" },
      { title: "Check passport and visa requirements", description: "Ensure documents are valid and apply for visa if needed", type: "task", priority: "high" },
      { title: "Purchase travel insurance", description: "Get coverage for trip cancellation and medical emergencies", type: "task", priority: "medium" },
      { title: "Pack luggage", description: "Prepare clothes and essentials for the trip", type: "task", priority: "low" },
      { title: "Arrange transportation to airport", description: "Book taxi, parking, or ask someone for a ride", type: "task", priority: "low" }
    ]
  end

  def generate_project_items(title)
    [
      { title: "Define project scope and objectives", description: "Clearly outline what the project will accomplish", type: "milestone", priority: "high" },
      { title: "Identify stakeholders and team members", description: "Determine who will be involved and their roles", type: "task", priority: "high" },
      { title: "Create project timeline", description: "Develop schedule with milestones and deadlines", type: "task", priority: "high" },
      { title: "Conduct kickoff meeting", description: "Align team on goals, expectations, and next steps", type: "milestone", priority: "medium" },
      { title: "Set up project management tools", description: "Configure tracking systems and communication channels", type: "task", priority: "medium" },
      { title: "Plan resource allocation", description: "Determine budget, tools, and personnel needs", type: "task", priority: "medium" },
      { title: "Establish communication protocols", description: "Define how and when team will communicate updates", type: "task", priority: "low" }
    ]
  end

  def generate_goals_items(title)
    [
      { title: "Define specific, measurable outcomes", description: "Set clear success criteria for the goal", type: "goal", priority: "high" },
      { title: "Break down into smaller milestones", description: "Create achievable steps toward the main goal", type: "milestone", priority: "high" },
      { title: "Set target completion date", description: "Establish realistic timeline for achievement", type: "milestone", priority: "medium" },
      { title: "Identify required resources", description: "Determine what you need to succeed", type: "task", priority: "medium" },
      { title: "Create accountability system", description: "Set up tracking and progress review process", type: "task", priority: "medium" },
      { title: "Plan celebration for achievement", description: "Decide how to reward yourself when goal is met", type: "reminder", priority: "low" }
    ]
  end

  def generate_shopping_items(title)
    [
      { title: "Create shopping list", description: "List all items needed", type: "task", priority: "high" },
      { title: "Set budget", description: "Determine spending limit", type: "task", priority: "medium" },
      { title: "Research prices and stores", description: "Compare prices and find best deals", type: "research", priority: "medium" },
      { title: "Check for coupons and discounts", description: "Look for savings opportunities", type: "task", priority: "low" }
    ]
  end

  def generate_wedding_items(title)
    [
      { title: "Set wedding date", description: "Choose date and check venue availability", type: "milestone", priority: "high" },
      { title: "Book venue", description: "Reserve ceremony and reception locations", type: "booking", priority: "high" },
      { title: "Create guest list", description: "Compile list of invitees", type: "task", priority: "high" },
      { title: "Send save the dates", description: "Give guests advance notice", type: "task", priority: "medium" },
      { title: "Choose wedding party", description: "Select bridesmaids, groomsmen, and officiant", type: "task", priority: "medium" }
    ]
  end

  def generate_moving_items(title)
    [
      { title: "Research moving companies", description: "Get quotes and book movers", type: "research", priority: "high" },
      { title: "Start packing non-essentials", description: "Pack items not needed daily", type: "task", priority: "medium" },
      { title: "Change address with utilities", description: "Update address for utilities, mail, subscriptions", type: "task", priority: "medium" },
      { title: "Pack essential box for first day", description: "Prepare items needed immediately in new home", type: "task", priority: "low" }
    ]
  end

  def generate_generic_planning_items(title, context)
    [
      { title: "Research and gather information", description: "Collect relevant information about #{context}", type: "research", priority: "high" },
      { title: "Create detailed plan", description: "Develop step-by-step approach", type: "task", priority: "high" },
      { title: "Set timeline and milestones", description: "Establish important dates and checkpoints", type: "milestone", priority: "medium" },
      { title: "Identify required resources", description: "Determine what you'll need to succeed", type: "task", priority: "medium" }
    ]
  end

  # Result class for consistent return values
  class Result
    attr_reader :data, :errors

    def initialize(success, data = nil, errors = [])
      @success = success
      @data = data
      @errors = errors
    end

    def success?
      @success
    end

    def self.success(data)
      new(true, data)
    end

    def self.failure(errors)
      new(false, nil, Array(errors))
    end
  end
end

# app/services/list_item_service.rb
class ListItemService
  include ServiceBroadcasting  # Use service-safe broadcasting instead

  attr_reader :list, :user, :errors

  def initialize(list, user)
    @list = list
    @user = user
    @errors = []
  end

  # Create a new list item
  def create_item(title:, description: nil, skip_broadcasts: false, **options)
    # Validate permissions
    unless can_edit_list?
      return Result.failure("You don't have permission to add items to this list")
    end

    # Use database transaction with locking to handle position conflicts
    item = nil
    ActiveRecord::Base.transaction do
      @list.with_lock do
        # Calculate position if not provided
        position = options[:position]
        if position.nil?
          max_position = @list.list_items.maximum(:position) || -1
          position = max_position + 1
        end

        # Auto-generate description if not provided
        if description.blank?
          description = generate_item_description(title)
        end

        # Create the item
        item = @list.list_items.build(
          title: title,
          description: description,
          position: position,
          item_type: options[:item_type] || determine_item_type(title),
          priority: options[:priority] || :medium,
          **options.slice(:due_date, :reminder_at, :assigned_user_id, :url, :metadata, :completed)
        )

        unless item.save
          @errors = item.errors.full_messages
          raise ActiveRecord::Rollback, "Failed to save item"
        end
      end
    end

    if item&.persisted?
      # Reload list to get updated counts
      @list.reload

      # Only broadcast if not explicitly skipped
      unless skip_broadcasts
        broadcast_item_creation(item)
      end

      Result.success(item)
    else
      Result.failure(@errors.presence || [ "Failed to create item" ])
    end
  rescue => e
    @errors = [ e.message ]
    Result.failure(@errors)
  end

  # Complete an item
  def complete_item(item_id)
    item = find_item(item_id)
    return Result.failure("Item not found") unless item

    unless can_edit_list?
      return Result.failure("You don't have permission to modify items in this list")
    end

    if item.update(completed: true, completed_at: Time.current)
      @list.reload
      broadcast_item_completion(item)
      Result.success(item)
    else
      @errors = item.errors.full_messages
      Result.failure(@errors)
    end
  end

  # Update an item
  def update_item(item_id, **attributes)
    item = find_item(item_id)
    return Result.failure("Item not found") unless item

    unless can_edit_list?
      return Result.failure("You don't have permission to modify items in this list")
    end

    if item.update(attributes)
      @list.reload
      broadcast_item_update(item)
      Result.success(item)
    else
      @errors = item.errors.full_messages
      Result.failure(@errors)
    end
  end

  # Delete an item
  def delete_item(item_id)
    item = find_item(item_id)
    return Result.failure("Item not found") unless item

    unless can_edit_list?
      return Result.failure("You don't have permission to modify items in this list")
    end

    if item.destroy
      @list.reload
      broadcast_item_deletion(item)
      Result.success(item)
    else
      @errors = [ "Failed to delete item" ]
      Result.failure(@errors)
    end
  end

  # Reorder items
  def reorder_items(item_positions)
    unless can_edit_list?
      return Result.failure("You don't have permission to reorder items in this list")
    end

    ActiveRecord::Base.transaction do
      item_positions.each do |item_id, position|
        item = @list.list_items.find(item_id)
        item.skip_notifications = true # Avoid spamming notifications for reordering
        item.update!(position: position.to_i)
      end
    end

    @list.reload
    broadcast_all_updates(@list)
    Result.success(@list)
  rescue => e
    @errors = [ e.message ]
    Result.failure(@errors)
  end

  # Bulk operations
  def bulk_complete_items(item_ids)
    unless can_edit_list?
      return Result.failure("You don't have permission to modify items in this list")
    end

    completed_items = []
    ActiveRecord::Base.transaction do
      item_ids.each do |item_id|
        item = find_item(item_id)
        next unless item

        if item.update(completed: true, completed_at: Time.current)
          completed_items << item
        end
      end
    end

    @list.reload
    broadcast_all_updates(@list)
    Result.success(completed_items)
  rescue => e
    @errors = [ e.message ]
    Result.failure(@errors)
  end

  private

  def find_item(item_id)
    @list.list_items.find_by(id: item_id)
  end

  def can_edit_list?
    return true if @list.user_id == @user.id

    collaboration = @list.list_collaborations.find_by(user: @user)
    collaboration&.permission_collaborate?
  end

  def generate_item_description(title)
    context = @list.title.downcase
    case title.downcase
    when /book|reserve/
      "Research options and make reservation"
    when /pack|packing/
      "Gather and organize necessary items"
    when /research|find/
      "Search for information and compare options"
    when /buy|purchase|get/
      "Locate and acquire this item"
    when /plan|planning/
      "Create detailed plan and timeline"
    when /contact|reach out|invite/
      "Communicate with relevant people"
    when /setup|set up|configure/
      "Establish and configure necessary systems"
    else
      "Complete this task for #{context}"
    end
  end

  def determine_item_type(title)
    title_lower = title.downcase

    case title_lower
    when /goal|objective|target/
      "goal"
    when /milestone|deadline|due/
      "milestone"
    when /remind|remember|don't forget/
      "reminder"
    when /waiting|pending|blocked/
      "waiting_for"
    when /research|investigate|find out/
      "research"
    when /book|reserve|schedule/
      "booking"
    when /buy|purchase|order/
      "purchase"
    else
      "task" # Default to task
    end
  end

  # Broadcasting methods
  def broadcast_item_creation(item)
    # Broadcast to list show page if user is viewing the list
    Turbo::StreamsChannel.broadcast_append_to(
      "list_#{@list.id}",
      target: "list-items",
      partial: "list_items/item",
      locals: { list_item: item, list: @list }
    )

    # Update dashboard for affected users
    broadcast_all_updates(@list)
  end

  def broadcast_item_completion(item)
    # Broadcast item update to list show page
    Turbo::StreamsChannel.broadcast_replace_to(
      "list_#{@list.id}",
      target: "list_item_#{item.id}",
      partial: "list_items/item",
      locals: { list_item: item, list: @list }
    )

    # Update dashboard for affected users
    broadcast_all_updates(@list)
  end

  def broadcast_item_update(item)
    # Broadcast item update to list show page
    Turbo::StreamsChannel.broadcast_replace_to(
      "list_#{@list.id}",
      target: "list_item_#{item.id}",
      partial: "list_items/item",
      locals: { list_item: item, list: @list }
    )

    # Update dashboard for affected users
    broadcast_all_updates(@list)
  end

  def broadcast_item_deletion(item)
    # Remove item from list show page
    Turbo::StreamsChannel.broadcast_remove_to(
      "list_#{@list.id}",
      target: "list_item_#{item.id}"
    )

    # Update dashboard for affected users
    broadcast_all_updates(@list)
  end

  # Result class for consistent return values
  class Result
    attr_reader :data, :errors

    def initialize(success, data = nil, errors = [])
      @success = success
      @data = data
      @errors = errors
    end

    def success?
      @success
    end

    def self.success(data)
      new(true, data)
    end

    def self.failure(errors)
      new(false, nil, Array(errors))
    end
  end
end
