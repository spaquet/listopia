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
  def create_list(title:, description: nil, **options)
    @list = @user.lists.build(
      title: title,
      description: description,
      status: options[:status] || :active,
      **options.slice(:is_public, :list_type, :color_theme)
    )

    if @list.save
      broadcast_all_updates(@list)
      Result.success(@list)
    else
      @errors = @list.errors.full_messages
      Result.failure(@errors)
    end
  end

  # Create a planning list with auto-generated items
  def create_planning_list(title:, description: nil, planning_context: nil, **options)
    ActiveRecord::Base.transaction do
      # Create the list first WITHOUT any broadcasting (prevent duplicates)
      @list = @user.lists.build(
        title: title,
        description: description,
        status: options[:status] || :active,
        **options.slice(:is_public, :list_type, :color_theme)
      )

      unless @list.save
        @errors = @list.errors.full_messages
        return Result.failure(@errors)
      end

      # Add planning items if context provided
      if planning_context.present?
        items_service = ListItemService.new(@list, @user)
        suggested_items = generate_planning_items(planning_context, title)

        suggested_items.each_with_index do |item_data, index|
          # Create items without individual broadcasts
          item_result = items_service.create_item(
            title: item_data[:title],
            description: item_data[:description],
            item_type: item_data[:type] || "task",
            priority: item_data[:priority] || "medium",
            position: index,
            skip_broadcasts: true  # Prevent individual item broadcasts
          )

          unless item_result.success?
            raise ActiveRecord::Rollback, "Failed to create planning items"
          end
        end
      end

      # Reload the list to get proper counts and associations
      @list.reload

      # Single broadcast AFTER everything is complete
      # Only broadcast to lists index, not dashboard (to prevent duplication)
      broadcast_lists_index_updates(@list)

      Result.success(@list)
    end
  rescue => e
    @errors = [e.message]
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
