# app/services/list_creation_service.rb
class ListCreationService < ApplicationService
  include ServiceBroadcasting

  attr_accessor :user, :list
  attr_reader :errors

  def initialize(user)
    @user = user
    @errors = []
  end

  # Create a basic list
  def create_list(title:, description: nil, **options)
    @list = @user.lists.build(
      title: title,
      description: description,
      status: :active,
      **options
    )

    if @list.save
      broadcast_all_updates(@list)
      Result.success(data: @list)
    else
      @errors = @list.errors.full_messages
      Result.failure(errors: @errors)
    end
  end

  # Create a planning list with AI-generated items
  def create_planning_list(title:, description: nil, planning_context: nil, **options)
    ActiveRecord::Base.transaction do
      # Create the list first
      @list = @user.lists.create!(
        title: title,
        description: description,
        status: :active,
        **options
      )

      # Generate planning items using AI if context is provided
      if planning_context.present?
        planning_items = generate_smart_planning_items(title, description, planning_context)

        planning_items.each_with_index do |item_data, index|
          items_service = ListItemService.new(@list, @user)
          item_result = items_service.create_item(
            title: item_data[:title],
            description: item_data[:description],
            item_type: item_data[:type] || "task",
            priority: item_data[:priority] || "medium",
            position: index,
            due_date: item_data[:due_date],
            url: item_data[:url],
            metadata: item_data[:metadata] || {}
          )

          unless item_result.success?
            Rails.logger.warn "Failed to create planning item: #{item_result.errors}"
            # Continue creating other items even if one fails
          end
        end
      end

      # Reload to get the latest items
      @list.reload
      broadcast_all_updates(@list)

      Result.success(data: @list)
    end
  rescue => e
    Rails.logger.error "Error creating planning list: #{e.message}"
    Result.failure(errors: [e.message])
  end

  private

  # Generate smart planning items based on context
  def generate_smart_planning_items(title, description, context)
    # This method should generate contextual planning items
    # For now, return some default items based on context
    case context.to_s.downcase
    when /trip|travel|vacation/
      [
        { title: "Book Air France flights", description: "Use Amex card for booking", type: "task", priority: "high" },
        { title: "Reserve accommodation", description: "Find hotel or Airbnb in Paris", type: "task", priority: "high" },
        { title: "Plan itinerary", description: "Research attractions and activities", type: "task", priority: "medium" },
        { title: "Check passport validity", description: "Ensure passport is valid for travel", type: "task", priority: "high" },
        { title: "Pack essentials", description: "Create packing checklist", type: "task", priority: "low" },
        { title: "Travel insurance", description: "Consider travel insurance options", type: "task", priority: "medium" }
      ]
    when /event|party|celebration/
      [
        { title: "Set date and time", description: "Confirm availability with key attendees", type: "task", priority: "high" },
        { title: "Create guest list", description: "Determine who to invite", type: "task", priority: "high" },
        { title: "Send invitations", description: "Send save the dates or invitations", type: "task", priority: "medium" },
        { title: "Plan menu", description: "Decide on food and beverages", type: "task", priority: "medium" },
        { title: "Arrange decorations", description: "Theme and decoration planning", type: "task", priority: "low" }
      ]
    when /project|work|business/
      [
        { title: "Define project scope", description: "Outline project objectives and deliverables", type: "task", priority: "high" },
        { title: "Assemble team", description: "Identify and assign team members", type: "task", priority: "high" },
        { title: "Create timeline", description: "Establish milestones and deadlines", type: "task", priority: "medium" },
        { title: "Set up communication", description: "Establish team communication channels", type: "task", priority: "medium" },
        { title: "Risk assessment", description: "Identify potential risks and mitigation strategies", type: "task", priority: "low" }
      ]
    else
      [
        { title: "Define objectives", description: "Clarify what you want to achieve", type: "task", priority: "high" },
        { title: "Research requirements", description: "Gather necessary information", type: "task", priority: "medium" },
        { title: "Create action plan", description: "Break down into actionable steps", type: "task", priority: "medium" },
        { title: "Set timeline", description: "Establish deadlines and milestones", type: "task", priority: "low" }
      ]
    end
  end
end
