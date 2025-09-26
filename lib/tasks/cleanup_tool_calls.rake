# lib/tasks/cleanup_tool_calls.rake
namespace :listopia do
  namespace :cleanup do
    desc "Clean up orphaned tool calls and malformed tool responses"
    task tool_calls: :environment do
      puts "Starting tool call cleanup..."

      total_cleaned = 0

      # Step 1: Clean up tool messages without tool_call_id
      orphaned_tool_messages = Message.where(role: "tool", tool_call_id: [ nil, "" ])
      if orphaned_tool_messages.any?
        count = orphaned_tool_messages.count
        puts "Removing #{count} tool messages without tool_call_id..."
        orphaned_tool_messages.destroy_all
        total_cleaned += count
      end

      # Step 2: Clean up tool messages with invalid tool_call_id format
      invalid_format_messages = Message.where(role: "tool")
                                      .where.not(tool_call_id: [ nil, "" ])
                                      .where.not("tool_call_id LIKE 'call_%'")
      if invalid_format_messages.any?
        count = invalid_format_messages.count
        puts "Removing #{count} tool messages with invalid tool_call_id format..."
        invalid_format_messages.destroy_all
        total_cleaned += count
      end

      # Step 3: Clean up tool messages without corresponding tool calls
      orphaned_responses = Message.where(role: "tool")
                                 .where.not(tool_call_id: [ nil, "" ])
                                 .includes(chat: :tool_calls)
                                 .select do |msg|
        !msg.chat.tool_calls.exists?(tool_call_id: msg.tool_call_id)
      end

      if orphaned_responses.any?
        count = orphaned_responses.count
        puts "Removing #{count} tool response messages without corresponding tool calls..."
        orphaned_responses.each(&:destroy!)
        total_cleaned += count
      end

      # Step 4: Clean up assistant messages with orphaned tool calls
      Chat.includes(messages: :tool_calls).find_each do |chat|
        assistant_messages = chat.messages.where(role: "assistant").includes(:tool_calls)

        assistant_messages.each do |msg|
          next unless msg.tool_calls.any?

          # Check if all tool calls have responses
          missing_responses = msg.tool_calls.select do |tc|
            !chat.messages.exists?(role: "tool", tool_call_id: tc.tool_call_id)
          end

          if missing_responses.any?
            puts "Removing assistant message #{msg.id} with #{missing_responses.count} orphaned tool calls"
            msg.destroy!
            total_cleaned += 1
          end
        end
      end

      # Step 5: Update chat states
      chats_needing_repair = Chat.where(conversation_state: [ "needs_cleanup", "error" ])
      if chats_needing_repair.any?
        puts "Marking #{chats_needing_repair.count} chats as stable..."
        chats_needing_repair.update_all(
          conversation_state: "stable",
          last_stable_at: Time.current
        )
      end

      puts "Cleanup completed! Cleaned up #{total_cleaned} problematic records."

      # Step 6: Generate summary report
      puts "\n=== Summary Report ==="
      puts "Total messages: #{Message.count}"
      puts "Tool messages: #{Message.where(role: 'tool').count}"
      puts "Tool calls: #{ToolCall.count}"
      puts "Chats with issues: #{Chat.select { |c| c.has_conversation_issues? }.count}"
      puts "Active chats: #{Chat.where(status: 'active').count}"
    end

    desc "Validate all conversations for integrity"
    task validate_conversations: :environment do
      puts "Validating all conversations..."

      issues_found = 0

      Chat.active_chats.includes(messages: :tool_calls).find_each do |chat|
        begin
          conversation_manager = ConversationStateManager.new(chat)
          conversation_manager.ensure_conversation_integrity!
          print "."
        rescue ConversationStateManager::ConversationError => e
          issues_found += 1
          puts "\nIssue found in chat #{chat.id}: #{e.message}"

          # Attempt repair
          begin
            cleanup_count = conversation_manager.perform_comprehensive_cleanup!
            puts "  → Repaired: cleaned #{cleanup_count} messages"
          rescue => repair_error
            puts "  → Repair failed: #{repair_error.message}"
          end
        end
      end

      puts "\nValidation completed!"
      puts "Issues found and repaired: #{issues_found}"
    end

    desc "Create conversation checkpoints for all active chats"
    task create_checkpoints: :environment do
      puts "Creating conversation checkpoints..."

      Chat.active_chats.find_each do |chat|
        begin
          chat.create_checkpoint!("cleanup_#{Time.current.to_i}")
          print "."
        rescue => e
          puts "\nFailed to create checkpoint for chat #{chat.id}: #{e.message}"
        end
      end

      puts "\nCheckpoints created!"
    end
  end
end
