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
      @list  # Return the list directly instead of Result object
    else
      @errors = @list.errors.full_messages
      raise StandardError, @errors.join(", ")
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

          # Handle the fact that ListItemService might still use Result pattern
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

          # Check if result is a Result object or direct response
          success = item_result.respond_to?(:success?) ? item_result.success? : item_result.present?
          unless success
            errors = item_result.respond_to?(:errors) ? item_result.errors : [ "Failed to create item" ]
            Rails.logger.warn "Failed to create planning item: #{errors}"
            # Continue creating other items even if one fails
          end
        end
      end

      # Reload to get the latest items
      @list.reload
      broadcast_all_updates(@list, action: :create)

      @list  # Return the list directly instead of Result object
    end
  rescue => e
    Rails.logger.error "Error creating planning list: #{e.message}"
    raise StandardError, e.message
  end

  private

  # Generate smart planning items using AI
  def generate_smart_planning_items(title, description, context)
    # Use the AI-powered PlanningItemGenerator
    generator = PlanningItemGenerator.new(title, description, context, @user)
    ai_items = generator.generate_items

    # If AI generation succeeds, use those items
    return ai_items if ai_items.present?

    # If AI generation fails completely, return empty array - let the AI agent handle it
    Rails.logger.warn "AI planning generation failed for '#{title}' with context '#{context}'"
    []
  end
end
