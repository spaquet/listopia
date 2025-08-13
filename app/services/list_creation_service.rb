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
      broadcast_all_updates(@list, action: :create)
      Result.success(@list)
    else
      @errors = @list.errors.full_messages
      Result.failure(@errors)
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
      broadcast_all_updates(@list, action: :create)

      Result.success(data: @list)
    end
  rescue => e
    Rails.logger.error "Error creating planning list: #{e.message}"
    Result.failure(errors: [ e.message ])
  end

  private

  # Generate smart planning items using AI
  def generate_smart_planning_items(title, description, context)
    # Use the existing PlanningItemGenerator to create AI-powered contextual items
    generator = PlanningItemGenerator.new(title, description, context, @user)
    ai_items = generator.generate_items

    # If AI generation succeeds, use those items
    return ai_items if ai_items.present?

    # Fallback to basic items if AI generation fails
    Rails.logger.warn "AI planning generation failed or returned no items, using fallback"
    generate_fallback_items(title, context)
  rescue => e
    Rails.logger.error "Error in generate_smart_planning_items: #{e.message}"
    generate_fallback_items(title, context)
  end

  # Fallback items when AI generation fails
  def generate_fallback_items(title, context)
    [
      {
        title: "Define objectives and scope",
        description: "Clearly outline what you want to achieve with this #{context || 'project'}",
        type: "milestone",
        priority: "high"
      },
      {
        title: "Research and gather requirements",
        description: "Collect all necessary information and identify what you need",
        type: "task",
        priority: "high"
      },
      {
        title: "Create detailed timeline",
        description: "Break down the work into phases with realistic deadlines",
        type: "task",
        priority: "medium"
      },
      {
        title: "Identify resources and budget",
        description: "Determine what resources, people, and budget you'll need",
        type: "task",
        priority: "medium"
      },
      {
        title: "Begin execution",
        description: "Start implementing your plan step by step",
        type: "milestone",
        priority: "medium"
      },
      {
        title: "Review and adjust",
        description: "Track progress and make adjustments as needed",
        type: "task",
        priority: "low"
      }
    ]
  end
end
