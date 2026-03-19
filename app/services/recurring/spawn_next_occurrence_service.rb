module Recurring
  class SpawnNextOccurrenceService < ApplicationService
    def initialize(list_item)
      @item = list_item
    end

    def call
      return success(data: nil) unless @item.recurring?
      return success(data: nil) unless @item.within_recurrence_window?

      new_item = @item.list.list_items.build(spawn_attributes)
      new_item.skip_notifications = true
      if new_item.save
        success(data: new_item)
      else
        failure(errors: new_item.errors.full_messages)
      end
    end

    private

    def spawn_attributes
      # Calculate next position to avoid unique constraint conflicts
      max_position = @item.list.list_items.maximum(:position) || -1

      {
        title: @item.title,
        description: @item.description,
        item_type: @item.item_type,
        priority: @item.priority,
        recurrence_rule: @item.recurrence_rule,
        recurrence_end_date: @item.recurrence_end_date,
        due_date: @item.next_due_date,
        assigned_user_id: @item.assigned_user_id,
        status: :pending,
        position: max_position + 1
      }
    end
  end
end
