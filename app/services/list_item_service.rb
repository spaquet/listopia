# app/services/list_item_service.rb

# Common service for managing list items
# Used by ListController and ListPlanningController
# Handles item creation, updates, completion, deletion, and bulk operations
# Also includes broadcasting updates to the list show page and dashboard

require "active_record"
require "turbo-rails"

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

      ApplicationService::Result.success(data: item)
    else
      ApplicationService::Result.failure(errors: @errors.presence || [ "Failed to create item" ])
    end
  rescue => e
    @errors = [ e.message ]
    ApplicationService::Result.failure(errors: @errors)
  end

  # Bulk create multiple items at once
  # This method is used by ListCreationService and chat system to create items in batch
  # Handles both Hash and String item data formats
  #
  # Benefits of using this service:
  # - Consistent position management (handles unique constraint conflicts)
  # - Permission validation and error handling
  # - Proper Turbo Stream broadcasting
  # - Database locking to prevent race conditions
  # - Supports skipping broadcasts for nested operations
  #
  # Usage:
  #   service = ListItemService.new(list, user)
  #   result = service.bulk_create_items([
  #     {title: "Item 1", description: "First item"},
  #     {title: "Item 2"},
  #     "Item 3"  # String format also supported
  #   ])
  def bulk_create_items(items_data, skip_broadcasts: false)
    unless can_edit_list?
      return ApplicationService::Result.failure(errors: ["You don't have permission to add items to this list"])
    end

    created_items = []

    begin
      ActiveRecord::Base.transaction do
        @list.with_lock do
          max_position = @list.list_items.maximum(:position) || -1

          items_data.each_with_index do |item_data, index|
            # Extract item attributes - supports both Hash and String formats
            item_title = item_data.is_a?(Hash) ? (item_data["title"] || item_data[:title]) : item_data.to_s
            item_description = item_data.is_a?(Hash) ? (item_data["description"] || item_data[:description]) : nil

            next unless item_title.present?

            # Calculate position - prevents unique constraint violations
            position = max_position + index + 1

            # Auto-generate description if not provided
            if item_description.blank?
              item_description = generate_item_description(item_title)
            end

            # Create the item
            item = @list.list_items.build(
              title: item_title,
              description: item_description,
              position: position,
              status: "pending",
              item_type: determine_item_type(item_title),
              priority: :medium
            )

            if item.save
              created_items << item
            else
              Rails.logger.warn "Failed to create item in list #{@list.id}: #{item.errors.full_messages}"
            end
          end
        end
      end

      @list.reload

      # Only broadcast if not explicitly skipped
      unless skip_broadcasts
        broadcast_all_updates(@list)
      end

      ApplicationService::Result.success(data: created_items)
    rescue => e
      @errors = [e.message]
      Rails.logger.error "Error bulk creating items: #{e.message}"
      ApplicationService::Result.failure(errors: @errors)
    end
  end

  # Complete an item
  def complete_item(item_id)
    item = find_item(item_id)
    return ApplicationService::Result.failure(errors: "Item not found") unless item

    unless can_edit_list?
      return ApplicationService::Result.failure(errors: "You don't have permission to modify items in this list")
    end

    if item.update(completed: true, status_changed_at: Time.current)
      @list.reload
      broadcast_item_completion(item)
      ApplicationService::Result.success(data: item)
    else
      @errors = item.errors.full_messages
      ApplicationService::Result.failure(errors: @errors)
    end
  end

  # Update an item
  def update_item(item_id, **attributes)
    item = find_item(item_id)
    return ApplicationService::Result.failure(errors: "Item not found") unless item

    unless can_edit_list?
      return ApplicationService::Result.failure(errors: "You don't have permission to modify items in this list")
    end

    if item.update(attributes)
      @list.reload
      broadcast_item_update(item)
      ApplicationService::Result.success(data: item)
    else
      @errors = item.errors.full_messages
      ApplicationService::Result.failure(errors: @errors)
    end
  end

  # Delete an item
  def delete_item(item_id)
    item = find_item(item_id)
    return ApplicationService::Result.failure(errors: "Item not found") unless item

    unless can_edit_list?
      return ApplicationService::Result.failure(errors: "You don't have permission to modify items in this list")
    end

    if item.destroy
      @list.reload
      broadcast_item_deletion(item)
      ApplicationService::Result.success(data: item)
    else
      @errors = [ "Failed to delete item" ]
      ApplicationService::Result.failure(errors: @errors)
    end
  end

  # Reorder items
  def reorder_items(item_positions)
    unless can_edit_list?
      return ApplicationService::Result.failure(errors: "You don't have permission to reorder items in this list")
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
    ApplicationService::Result.success(data: @list)
  rescue => e
    @errors = [ e.message ]
    ApplicationService::Result.failure(errors: @errors)
  end

  # Bulk operations
  def bulk_complete_items(item_ids)
    unless can_edit_list?
      return ApplicationService::Result.failure(errors: "You don't have permission to modify items in this list")
    end

    completed_items = []
    ActiveRecord::Base.transaction do
      item_ids.each do |item_id|
        item = find_item(item_id)
        next unless item

        if item.update(completed: true, status_changed_at: Time.current)
          completed_items << item
        end
      end
    end

    @list.reload
    broadcast_all_updates(@list)
    ApplicationService::Result.success(data: completed_items)
  rescue => e
    @errors = [ e.message ]
    ApplicationService::Result.failure(errors: @errors)
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
      locals: { item: item, list: @list, current_user: @user }
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
      locals: { item: item, list: @list, current_user: @user }
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
      locals: { item: item, list: @list, current_user: @user }
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
end
