#!/usr/bin/env ruby
# bin/upgrade_database.rb
#
# Independent script to upgrade existing database with tool call constraints
# Run with: ruby bin/upgrade_database.rb

require 'bundler/setup'
require_relative '../config/environment'

class DatabaseUpgrader
  def initialize
    @connection = ActiveRecord::Base.connection
    puts "Database Upgrade Script for Tool Call Constraints"
    puts "=" * 50
  end

  def run!
    puts "Starting database upgrade..."

    # Step 1: Clean existing problematic data
    clean_existing_data!

    # Step 2: Add constraints and indexes
    add_constraints_and_indexes!

    # Step 3: Verify the upgrade
    verify_upgrade!

    puts "\n✅ Database upgrade completed successfully!"
  end

  private

  def clean_existing_data!
    puts "\n🧹 Cleaning existing problematic data..."

    total_cleaned = 0

    # Clean up tool messages without tool_call_id
    orphaned_tool_messages = Message.where(role: "tool", tool_call_id: [ nil, "" ])
    if orphaned_tool_messages.any?
      count = orphaned_tool_messages.count
      puts "  → Removing #{count} tool messages without tool_call_id..."
      orphaned_tool_messages.destroy_all
      total_cleaned += count
    end

    # Clean up tool messages with invalid tool_call_id format
    invalid_format_messages = Message.where(role: "tool")
                                    .where.not(tool_call_id: [ nil, "" ])
                                    .where.not("tool_call_id LIKE 'call_%'")
    if invalid_format_messages.any?
      count = invalid_format_messages.count
      puts "  → Removing #{count} tool messages with invalid tool_call_id format..."
      invalid_format_messages.destroy_all
      total_cleaned += count
    end

    # Clean up tool messages without corresponding tool calls
    orphaned_responses = Message.where(role: "tool")
                               .where.not(tool_call_id: [ nil, "" ])
                               .includes(chat: :tool_calls)
                               .select do |msg|
      !msg.chat.tool_calls.exists?(tool_call_id: msg.tool_call_id)
    end

    if orphaned_responses.any?
      count = orphaned_responses.count
      puts "  → Removing #{count} tool response messages without corresponding tool calls..."
      orphaned_responses.each(&:destroy!)
      total_cleaned += count
    end

    # Clean up assistant messages with orphaned tool calls
    Chat.includes(messages: :tool_calls).find_each do |chat|
      assistant_messages = chat.messages.where(role: "assistant").includes(:tool_calls)

      assistant_messages.each do |msg|
        next unless msg.tool_calls.any?

        # Check if all tool calls have responses
        missing_responses = msg.tool_calls.select do |tc|
          !chat.messages.exists?(role: "tool", tool_call_id: tc.tool_call_id)
        end

        if missing_responses.any?
          puts "  → Removing assistant message #{msg.id} with #{missing_responses.count} orphaned tool calls"
          msg.destroy!
          total_cleaned += 1
        end
      end
    end

    puts "  ✅ Cleaned #{total_cleaned} problematic records"
  end

  def add_constraints_and_indexes!
    puts "\n🔧 Adding constraints and indexes..."

    # Check if constraint already exists
    unless constraint_exists?("tool_messages_must_have_tool_call_id")
      puts "  → Adding check constraint: tool_messages_must_have_tool_call_id"
      @connection.execute(<<~SQL)
        ALTER TABLE messages
        ADD CONSTRAINT tool_messages_must_have_tool_call_id
        CHECK (role != 'tool' OR tool_call_id IS NOT NULL)
      SQL
    else
      puts "  ✓ Check constraint already exists: tool_messages_must_have_tool_call_id"
    end

    # Add index for better query performance on tool_call_id lookups
    unless index_exists?("index_messages_on_role_and_tool_call_id")
      puts "  → Adding index: index_messages_on_role_and_tool_call_id"
      @connection.execute(<<~SQL)
        CREATE INDEX index_messages_on_role_and_tool_call_id
        ON messages (role, tool_call_id)
        WHERE role = 'tool' AND tool_call_id IS NOT NULL
      SQL
    else
      puts "  ✓ Index already exists: index_messages_on_role_and_tool_call_id"
    end

    # Add unique constraint for tool_call_id within chat
    unless index_exists?("index_messages_unique_tool_call_id_per_chat")
      puts "  → Adding unique index: index_messages_unique_tool_call_id_per_chat"
      @connection.execute(<<~SQL)
        CREATE UNIQUE INDEX index_messages_unique_tool_call_id_per_chat
        ON messages (chat_id, tool_call_id)
        WHERE role = 'tool' AND tool_call_id IS NOT NULL
      SQL
    else
      puts "  ✓ Unique index already exists: index_messages_unique_tool_call_id_per_chat"
    end
  end

  def verify_upgrade!
    puts "\n🔍 Verifying upgrade..."

    # Test the constraint
    begin
      Message.create!(
        chat: Chat.first || Chat.create!(user: User.first, title: "Test"),
        role: "tool",
        content: "test",
        tool_call_id: nil
      )
      puts "  ❌ ERROR: Constraint not working - tool message created without tool_call_id"
      exit 1
    rescue ActiveRecord::StatementInvalid => e
      if e.message.include?("tool_messages_must_have_tool_call_id")
        puts "  ✅ Check constraint is working properly"
      else
        puts "  ❌ ERROR: Unexpected constraint error: #{e.message}"
        exit 1
      end
    end

    # Verify indexes exist
    indexes = @connection.execute(<<~SQL)
      SELECT indexname FROM pg_indexes
      WHERE tablename = 'messages'
      AND (
        indexname = 'index_messages_on_role_and_tool_call_id' OR
        indexname = 'index_messages_unique_tool_call_id_per_chat'
      )
    SQL

    if indexes.count == 2
      puts "  ✅ All indexes created successfully"
    else
      puts "  ❌ ERROR: Some indexes are missing"
      exit 1
    end

    # Check current data integrity
    tool_messages_without_id = Message.where(role: "tool", tool_call_id: [ nil, "" ])
    if tool_messages_without_id.any?
      puts "  ❌ ERROR: Found #{tool_messages_without_id.count} tool messages without tool_call_id"
      exit 1
    else
      puts "  ✅ No tool messages without tool_call_id found"
    end

    # Update chat states
    chats_needing_repair = Chat.where(conversation_state: [ "needs_cleanup", "error" ])
    if chats_needing_repair.any?
      puts "  → Marking #{chats_needing_repair.count} chats as stable..."
      chats_needing_repair.update_all(
        conversation_state: "stable",
        last_stable_at: Time.current
      )
    end
  end

  def constraint_exists?(constraint_name)
    result = @connection.execute(<<~SQL)
      SELECT 1 FROM information_schema.table_constraints
      WHERE constraint_name = '#{constraint_name}'
      AND table_name = 'messages'
    SQL
    result.any?
  end

  def index_exists?(index_name)
    result = @connection.execute(<<~SQL)
      SELECT 1 FROM pg_indexes
      WHERE indexname = '#{index_name}'
      AND tablename = 'messages'
    SQL
    result.any?
  end
end

# Run the upgrade
if __FILE__ == $0
  begin
    upgrader = DatabaseUpgrader.new
    upgrader.run!
  rescue => e
    puts "\n❌ Upgrade failed: #{e.message}"
    puts e.backtrace.join("\n")
    exit 1
  end
end
