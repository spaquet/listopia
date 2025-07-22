# app/services/list_creation_service.rb

# Common service for creating lists, including regular, planning, and duplicates
# Used by ListController and ListPlanningController
# handles list creation, planning item generation, and duplication
# Also includes broadcasting updates to the list show page and dashboard

require "active_record"
require "turbo-rails"

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
      unless skip_broadcasts
        broadcast_all_updates(@list)
      end
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

      @list = result.data

      # Add planning items if context provided
      if planning_context.present?
        items_service = ListItemService.new(@list, @user)
        suggested_items = generate_planning_items(planning_context, title)

        Rails.logger.info "Creating #{suggested_items.count} planning items for list #{@list.id}"

        suggested_items.each_with_index do |item_data, index|
          # Create items without individual broadcasts to prevent spam
          item_result = items_service.create_item(
            title: item_data[:title],
            description: item_data[:description],
            item_type: item_data[:type] || "task",
            priority: item_data[:priority] || "medium",
            position: index,
            skip_broadcasts: true  # Skip individual item broadcasts
          )

          unless item_result.success?
            Rails.logger.error "Failed to create planning item: #{item_result.errors.join(', ')}"
            raise ActiveRecord::Rollback, "Failed to create planning items: #{item_result.errors.join(', ')}"
          end
        end
      end

      # Reload the list to get proper counts and associations
      @list.reload
      Rails.logger.info "Planning list created with #{@list.list_items.count} items"

      # Single broadcast AFTER everything is complete
      broadcast_all_updates(@list)

      Result.success(@list)
    end
  rescue => e
    Rails.logger.error "Planning list creation failed: #{e.message}"
    @errors = [e.message]
    Result.failure(@errors)
  end

  # Duplicate an existing list
  def duplicate_list(source_list, new_title: nil)
    new_title ||= "Copy of #{source_list.title}"

    ActiveRecord::Base.transaction do
      # Create the new list without broadcasting first
      result = create_list(
        title: new_title,
        description: source_list.description,
        status: :active, # Always start duplicates as active
        list_type: source_list.list_type,
        color_theme: source_list.color_theme,
        skip_broadcasts: true  # Skip broadcasts during duplication
      )

      return result unless result.success?
      @list = result.data

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
          metadata: source_item.metadata,
          skip_broadcasts: true  # Skip individual item broadcasts
        )

        unless item_result.success?
          raise ActiveRecord::Rollback, "Failed to duplicate items"
        end
      end

      # Reload and broadcast final state
      @list.reload
      broadcast_all_updates(@list)
      Result.success(@list)
    end
  rescue => e
    @errors = [e.message]
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
      { title: "Coordinate accommodation for speakers", description: "Book hotels and arrange transportation for keynote speakers", type: "task", priority: "medium" },
      { title: "Setup A/V and technical requirements", description: "Test all audio/visual equipment, livestreaming, and recording setup", type: "task", priority: "high" },
      { title: "Plan networking events and social activities", description: "Organize welcome reception, networking breaks, and after-party", type: "task", priority: "low" },
      { title: "Prepare conference swag and materials", description: "Order branded items, badges, programs, and welcome packets", type: "task", priority: "low" },
      { title: "Finalize logistics and day-of coordination", description: "Create detailed timeline and assign staff responsibilities", type: "milestone", priority: "high" }
    ]
  end

  def generate_vacation_items(title)
    [
      { title: "Research destination and activities", description: "Explore attractions, local culture, and must-see locations", type: "idea", priority: "high" },
      { title: "Book flights or transportation", description: "Compare prices and book travel to destination", type: "task", priority: "high" },
      { title: "Reserve accommodation", description: "Book hotel, Airbnb, or other lodging for travel dates", type: "task", priority: "high" },
      { title: "Plan daily itinerary", description: "Create day-by-day schedule of activities and sightseeing", type: "task", priority: "medium" },
      { title: "Check passport and visa requirements", description: "Ensure documents are valid and obtain necessary visas", type: "task", priority: "high" },
      { title: "Pack luggage and essentials", description: "Prepare clothing and items appropriate for destination and activities", type: "task", priority: "medium" },
      { title: "Arrange travel insurance", description: "Purchase coverage for trip cancellation and medical emergencies", type: "task", priority: "medium" },
      { title: "Notify bank of travel plans", description: "Inform credit card companies to avoid transaction blocks", type: "task", priority: "medium" },
      { title: "Download offline maps and apps", description: "Prepare navigation and translation tools for destination", type: "task", priority: "low" },
      { title: "Confirm all reservations", description: "Double-check flights, hotels, and activity bookings", type: "milestone", priority: "medium" }
    ]
  end

  def generate_project_items(title)
    [
      { title: "Define project scope and objectives", description: "Clearly outline project goals, deliverables, and success criteria", type: "milestone", priority: "high" },
      { title: "Identify stakeholders and team members", description: "Map out all people involved and their roles in the project", type: "task", priority: "high" },
      { title: "Create project timeline and milestones", description: "Develop realistic schedule with key deadlines and dependencies", type: "task", priority: "high" },
      { title: "Estimate budget and resources needed", description: "Calculate costs and identify required tools, people, and materials", type: "task", priority: "medium" },
      { title: "Set up project management tools", description: "Configure tracking systems, communication channels, and file storage", type: "task", priority: "medium" },
      { title: "Conduct initial research and planning", description: "Gather information and create detailed project plan", type: "idea", priority: "medium" },
      { title: "Begin execution phase", description: "Start working on project deliverables according to timeline", type: "milestone", priority: "medium" },
      { title: "Schedule regular check-ins and reviews", description: "Plan progress meetings and status update cadence", type: "task", priority: "low" },
      { title: "Prepare for project completion and handoff", description: "Plan final deliverables, documentation, and transition", type: "task", priority: "low" }
    ]
  end

  def generate_goals_items(title)
    [
      { title: "Define specific and measurable goals", description: "Write clear, actionable objectives with success metrics", type: "milestone", priority: "high" },
      { title: "Break down goals into smaller steps", description: "Create actionable tasks that lead to goal achievement", type: "task", priority: "high" },
      { title: "Set realistic timeline and deadlines", description: "Establish achievable schedule with interim milestones", type: "task", priority: "medium" },
      { title: "Identify potential obstacles and solutions", description: "Anticipate challenges and prepare contingency plans", type: "task", priority: "medium" },
      { title: "Establish accountability system", description: "Set up tracking method and find accountability partner", type: "task", priority: "medium" },
      { title: "Schedule regular progress reviews", description: "Plan weekly/monthly check-ins to assess advancement", type: "task", priority: "low" },
      { title: "Celebrate milestones and achievements", description: "Plan rewards and recognition for progress made", type: "reminder", priority: "low" }
    ]
  end

  def generate_shopping_items(title)
    [
      { title: "Create comprehensive shopping list", description: "Write down all needed items organized by category", type: "task", priority: "high" },
      { title: "Set budget and price limits", description: "Determine spending limits for different categories", type: "task", priority: "medium" },
      { title: "Research best prices and deals", description: "Compare stores, online options, and current promotions", type: "idea", priority: "medium" },
      { title: "Check for coupons and discounts", description: "Look for manufacturer coupons, store sales, and cashback offers", type: "task", priority: "low" },
      { title: "Plan shopping route and timing", description: "Organize store visits efficiently and choose optimal shopping times", type: "task", priority: "low" }
    ]
  end

  def generate_wedding_items(title)
    [
      { title: "Set wedding date and budget", description: "Choose date and establish overall budget allocation", type: "milestone", priority: "high" },
      { title: "Book ceremony and reception venues", description: "Reserve locations for wedding ceremony and celebration", type: "task", priority: "high" },
      { title: "Create guest list and send invitations", description: "Finalize attendee list and mail save-the-dates and invitations", type: "task", priority: "high" },
      { title: "Choose and book wedding vendors", description: "Select photographer, caterer, florist, music, and other services", type: "task", priority: "medium" },
      { title: "Shop for wedding attire", description: "Choose and order wedding dress, suit, and accessories", type: "task", priority: "medium" },
      { title: "Plan wedding menu and cake", description: "Select catering options and design wedding cake", type: "task", priority: "medium" },
      { title: "Arrange transportation and accommodations", description: "Book transportation and room blocks for out-of-town guests", type: "task", priority: "low" },
      { title: "Plan honeymoon", description: "Research and book honeymoon destination and activities", type: "task", priority: "low" },
      { title: "Final preparations and rehearsal", description: "Confirm all details and conduct wedding rehearsal", type: "milestone", priority: "high" }
    ]
  end

  def generate_moving_items(title)
    [
      { title: "Research moving companies or rent truck", description: "Get quotes from movers or reserve moving truck", type: "idea", priority: "high" },
      { title: "Create moving timeline and checklist", description: "Plan moving schedule and tasks for each week", type: "task", priority: "high" },
      { title: "Sort and declutter belongings", description: "Decide what to keep, donate, sell, or throw away", type: "task", priority: "medium" },
      { title: "Order packing supplies", description: "Buy boxes, tape, bubble wrap, and packing materials", type: "task", priority: "medium" },
      { title: "Start packing non-essential items", description: "Pack seasonal items, books, and things not needed daily", type: "task", priority: "medium" },
      { title: "Update address with important services", description: "Notify bank, insurance, subscriptions, and government agencies", type: "task", priority: "high" },
      { title: "Transfer or setup utilities", description: "Arrange electricity, gas, water, internet, and cable services", type: "task", priority: "high" },
      { title: "Pack essential items and valuables", description: "Prepare important documents and daily necessities", type: "task", priority: "medium" },
      { title: "Supervise moving day", description: "Coordinate with movers and conduct final walkthrough", type: "milestone", priority: "high" }
    ]
  end

  def generate_generic_planning_items(title, context)
    [
      { title: "Define goals and objectives", description: "Clearly outline what needs to be accomplished", type: "milestone", priority: "high" },
      { title: "Research and gather information", description: "Collect relevant details and requirements for #{context}", type: "idea", priority: "medium" },
      { title: "Create detailed plan and timeline", description: "Develop step-by-step approach with realistic deadlines", type: "task", priority: "medium" },
      { title: "Identify required resources", description: "Determine what tools, people, or materials are needed", type: "task", priority: "medium" },
      { title: "Begin implementation", description: "Start executing the plan according to timeline", type: "milestone", priority: "medium" },
      { title: "Monitor progress and adjust", description: "Track advancement and make necessary modifications", type: "task", priority: "low" }
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
