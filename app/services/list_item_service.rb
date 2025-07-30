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
