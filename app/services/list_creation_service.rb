# app/services/list_creation_service.rb

# Common service for creating lists, including regular, planning, and duplicates
# Used by ListController and ListPlanningController
# handles list creation, planning item generation, and duplication
# Also includes broadcasting updates to the list show page and dashboard
class ListCreationService
  include ListBroadcasting

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
      # Create the list first
      result = create_list(title: title, description: description, **options)
      return result unless result.success?

      # Add planning items if context provided
      if planning_context.present?
        items_service = ListItemService.new(@list, @user)
        suggested_items = generate_planning_items(planning_context, title)

        suggested_items.each_with_index do |item_data, index|
          item_result = items_service.create_item(
            title: item_data[:title],
            description: item_data[:description],
            item_type: item_data[:type] || "task",
            priority: item_data[:priority] || "medium",
            position: index
          )

          unless item_result.success?
            raise ActiveRecord::Rollback, "Failed to create planning items"
          end
        end
      end

      # Broadcast final state after all items are created
      broadcast_all_updates(@list)
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

      # Copy all items
      items_service = ListItemService.new(@list, @user)
      source_list.list_items.order(:position).each do |source_item|
        item_result = items_service.create_item(
          title: source_item.title,
          description: source_item.description,
          item_type: source_item.item_type,
          priority: source_item.priority,
          due_date: source_item.due_date,
          position: source_item.position,
          completed: false # Reset completion status for duplicates
        )

        unless item_result.success?
          raise ActiveRecord::Rollback, "Failed to duplicate items"
        end
      end

      broadcast_all_updates(@list)
      Result.success(@list)
    end
  rescue => e
    @errors = [e.message]
    Result.failure(@errors)
  end

  private

  # Generate planning items based on context
  def generate_planning_items(context, title)
    case context.downcase
    when "vacation"
      [
        { title: "Research destination", description: "Look up attractions, weather, and local customs", type: "research", priority: "high" },
        { title: "Book accommodations", description: "Find and reserve hotel or rental", type: "booking", priority: "high" },
        { title: "Plan transportation", description: "Book flights or arrange travel", type: "booking", priority: "high" },
        { title: "Create packing list", description: "List essential items to bring", type: "task", priority: "medium" },
        { title: "Check travel documents", description: "Verify passport, visa, and ID requirements", type: "task", priority: "high" }
      ]
    when "project"
      [
        { title: "Define project scope", description: "Clarify objectives and deliverables", type: "goal", priority: "high" },
        { title: "Identify key stakeholders", description: "List people involved and their roles", type: "task", priority: "medium" },
        { title: "Create project timeline", description: "Set milestones and deadlines", type: "milestone", priority: "high" },
        { title: "Allocate resources", description: "Determine budget and team needs", type: "task", priority: "medium" }
      ]
    when "shopping"
      [
        { title: "Set budget", description: "Determine spending limit", type: "goal", priority: "high" },
        { title: "Compare prices", description: "Research costs at different stores", type: "research", priority: "medium" },
        { title: "Check for deals", description: "Look for coupons and discounts", type: "task", priority: "low" }
      ]
    when "goals"
      [
        { title: "Define success metrics", description: "How will you measure progress?", type: "goal", priority: "high" },
        { title: "Break into smaller steps", description: "Create actionable milestones", type: "milestone", priority: "high" },
        { title: "Set review schedule", description: "Plan regular progress check-ins", type: "reminder", priority: "medium" }
      ]
    when "event", "conference"
      [
        { title: "Define event scope and goals", description: "Clarify purpose, audience, and success metrics", type: "goal", priority: "high" },
        { title: "Secure venue", description: "Book location and confirm dates", type: "booking", priority: "high" },
        { title: "Create budget", description: "Estimate costs for all aspects", type: "task", priority: "high" },
        { title: "Invite speakers", description: "Contact and confirm keynote and session speakers", type: "task", priority: "high" },
        { title: "Plan agenda", description: "Create detailed schedule of sessions and activities", type: "task", priority: "medium" },
        { title: "Marketing and promotion", description: "Create marketing materials and promotion strategy", type: "task", priority: "medium" },
        { title: "Registration system", description: "Set up attendee registration and payment", type: "task", priority: "medium" },
        { title: "Catering arrangements", description: "Plan meals, snacks, and refreshments", type: "booking", priority: "medium" },
        { title: "Technical requirements", description: "Audio/visual equipment, internet, tech support", type: "task", priority: "medium" },
        { title: "Accommodation coordination", description: "Help speakers and attendees with lodging", type: "task", priority: "low" },
        { title: "Event materials", description: "Badges, swag, programs, signage", type: "task", priority: "low" },
        { title: "Post-event follow-up", description: "Thank you messages, feedback collection, next steps", type: "reminder", priority: "low" }
      ]
    else
      []
    end
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

    def failure?
      !@success
    end

    def self.success(data)
      new(true, data)
    end

    def self.failure(errors)
      new(false, nil, Array(errors))
    end
  end
end
