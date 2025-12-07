namespace :listopia do
  desc "Sync all list item statuses to match their board columns"
  task sync_item_status: :environment do
    List.find_each do |list|
      synced_count = 0
      total_count = 0

      list.list_items.find_each do |item|
        total_count += 1
        old_status = item.status

        if item.board_column
          new_status = case item.board_column.name
          when "To Do"
            :pending
          when "In Progress"
            :in_progress
          when "Done"
            :completed
          else
            item.status
          end

          if old_status != new_status
            item.status = new_status
            item.status_changed_at = Time.current

            if new_status == :completed
              item.completed_at = Time.current
            elsif new_status != :completed
              item.completed_at = nil
            end

            item.save!
            synced_count += 1

            puts "  ✓ #{item.title}: #{old_status} → #{new_status}"
          end
        end
      end

      puts "#{list.title}: synced #{synced_count}/#{total_count} items" if synced_count > 0
    end

    puts "\nSync complete!"
  end
end
