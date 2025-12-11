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
      ApplicationService::Result.success(data: @list)  # ← FIXED: Return Result object
    else
      @errors = @list.errors.full_messages
      ApplicationService::Result.failure(errors: @errors)  # ← FIXED: Return Result object
    end
  end

  # Create a list with items and optional nested sub-lists
  # This is the primary method used by chat system and can handle complex list structures
  #
  # Usage:
  #   service = ListCreationService.new(user)
  #   result = service.create_list_with_structure(
  #     title: "US Roadshow",
  #     description: "Planning roadshow across US",
  #     items: [{title: "Venue booking"}, {title: "Marketing"}],
  #     nested_lists: [
  #       {title: "New York", items: [{title: "Hotels"}, {title: "Transport"}]},
  #       {title: "Chicago", items: [{title: "Hotels"}]}
  #     ],
  #     organization: org,
  #     status: "active"
  #   )
  #
  # Benefits of using this service:
  # - Consistent validation and error handling across chat and UI
  # - Proper Turbo Stream broadcasting to keep dashboards in sync
  # - Centralized position management (handles constraint conflicts)
  # - Support for nested hierarchies
  # - Atomic transactions ensure data integrity
  # - Maintainability: list creation logic in one place
  def create_list_with_structure(
    title:,
    description: nil,
    items: [],
    nested_lists: [],
    organization: nil,
    **options
  )
    return ApplicationService::Result.failure(errors: ["List title is required"]) unless title.present?

    begin
      ActiveRecord::Base.transaction do
        # Create the parent list
        @list = @user.lists.build(
          title: title,
          description: description,
          organization: organization,
          **options
        )

        unless @list.save
          return ApplicationService::Result.failure(errors: @list.errors.full_messages)
        end

        # Create items for the parent list if provided
        if items.present?
          items_service = ListItemService.new(@list, @user)
          items_result = items_service.bulk_create_items(items, skip_broadcasts: true)

          unless items_result.success?
            Rails.logger.warn "Failed to create items for list #{@list.id}: #{items_result.errors}"
          end
        end

        # Create nested sub-lists if provided
        if nested_lists.present?
          nested_lists.each do |nested_structure|
            sublist_result = create_sublist(@list, nested_structure)

            unless sublist_result.success?
              Rails.logger.warn "Failed to create sub-list: #{sublist_result.errors}"
            end
          end
        end

        # Reload to get updated counts
        @list.reload

        # Broadcast creation to all affected users
        broadcast_all_updates(@list, action: :create)

        ApplicationService::Result.success(data: @list)
      end
    rescue => e
      Rails.logger.error "Error creating list with structure: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      ApplicationService::Result.failure(errors: [e.message])
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

      ApplicationService::Result.success(data: @list)  # ← FIXED: Return Result object
    end
  rescue => e
    Rails.logger.error "Error creating planning list: #{e.message}"
    @errors = [ e.message ]
    ApplicationService::Result.failure(errors: @errors)  # ← FIXED: Return Result object
  end

  private

  # Create a sub-list with items
  # Handles both Hash and String formats for nested structures
  # Returns ApplicationService::Result with created sub-list data
  def create_sublist(parent_list, structure)
    # Extract structure data - supports both string and symbol keys
    title = structure.is_a?(Hash) ? (structure["title"] || structure[:title]) : structure.to_s
    description = structure.is_a?(Hash) ? (structure["description"] || structure[:description]) : nil
    items = structure.is_a?(Hash) ? (structure["items"] || structure[:items] || []) : []

    return ApplicationService::Result.failure(errors: ["Sub-list title is required"]) unless title.present?

    begin
      # Create the sub-list
      sublist = List.new(
        organization: parent_list.organization,
        owner: @user,
        parent_list: parent_list,
        title: title,
        description: description,
        status: parent_list.status,
        list_type: parent_list.list_type,
        team_id: parent_list.team_id
      )

      unless sublist.save
        return ApplicationService::Result.failure(errors: sublist.errors.full_messages)
      end

      # Create items for the sub-list if provided
      if items.present?
        items_service = ListItemService.new(sublist, @user)
        items_result = items_service.bulk_create_items(items, skip_broadcasts: true)

        unless items_result.success?
          Rails.logger.warn "Failed to create items for sub-list #{sublist.id}: #{items_result.errors}"
        end
      end

      ApplicationService::Result.success(data: {
        sublist: sublist,
        items_count: sublist.list_items.count
      })
    rescue => e
      Rails.logger.error "Error creating sub-list: #{e.message}"
      ApplicationService::Result.failure(errors: [e.message])
    end
  end

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
