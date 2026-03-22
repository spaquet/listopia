# lib/tasks/migrate_planning_context.rake
# Migration task: chat.metadata["pending_pre_creation_planning"] → PlanningContext

namespace :planning_context do
  desc "Migrate existing chat metadata to PlanningContext model"
  task migrate: :environment do
    puts "Starting migration of chat.metadata to PlanningContext..."

    migrated_count = 0
    skipped_count = 0
    error_count = 0

    Chat.find_each do |chat|
      begin
        # Check if chat already has a planning context
        if chat.planning_context.present?
          puts "  ⊘ Chat #{chat.id}: Already has planning_context, skipping"
          skipped_count += 1
          next
        end

        # Check if chat has pending_pre_creation_planning metadata
        pending = chat.metadata&.dig("pending_pre_creation_planning")
        unless pending.present?
          skipped_count += 1
          next
        end

        puts "  ⟳ Chat #{chat.id}: Migrating pending_pre_creation_planning..."

        # Extract data from metadata
        extracted_params = pending["extracted_params"] || {}
        questions_asked = pending["questions_asked"] || []
        refinement_context = pending["refinement_context"] || {}

        # Create planning context from metadata
        planning_context = PlanningContext.new(
          user: chat.user,
          chat: chat,
          organization: chat.organization,
          request_content: refinement_context["list_title"] || extracted_params["title"] || "Imported from chat",
          detected_intent: pending["intent"] || "create_list",
          planning_domain: refinement_context["category"]&.to_s || "personal",
          complexity_level: "unknown",
          is_complex: questions_asked.present?, # If questions were asked, assume complex
          parameters: extracted_params || {},
          pre_creation_questions: questions_asked || [],
          pre_creation_answers: {}, # Answers would have been collected separately
          state: :refinement, # These were in refinement stage when pending
          status: :awaiting_user_input,
          metadata: {
            migrated_from_chat_metadata: true,
            migration_source: "chat.metadata.pending_pre_creation_planning",
            migrated_at: Time.current.iso8601
          }
        )

        if planning_context.save
          puts "    ✓ Chat #{chat.id}: Migrated successfully"
          migrated_count += 1
        else
          puts "    ✗ Chat #{chat.id}: Failed to save - #{planning_context.errors.full_messages.join(', ')}"
          error_count += 1
        end
      rescue => e
        puts "    ✗ Chat #{chat.id}: Error - #{e.message}"
        error_count += 1
      end
    end

    puts ""
    puts "Migration complete!"
    puts "  ✓ Migrated: #{migrated_count}"
    puts "  ⊘ Skipped: #{skipped_count}"
    puts "  ✗ Errors: #{error_count}"
  end

  desc "Verify planning context migration"
  task verify: :environment do
    puts "Verifying planning context migration..."

    total_chats = Chat.count
    chats_with_context = Chat.where.not(planning_context_id: nil).count
    chats_with_pending_metadata = Chat.where("metadata->>'pending_pre_creation_planning' IS NOT NULL").count

    puts ""
    puts "Chat Statistics:"
    puts "  Total chats: #{total_chats}"
    puts "  With planning_context: #{chats_with_context}"
    puts "  With pending_pre_creation_planning (metadata): #{chats_with_pending_metadata}"
    puts ""

    if chats_with_pending_metadata > 0 && chats_with_context >= chats_with_pending_metadata
      puts "✓ All chats with pending metadata have been migrated to planning_context"
    elsif chats_with_pending_metadata > 0
      puts "⚠ Some chats still have pending metadata not yet migrated:"
      Chat.where("metadata->>'pending_pre_creation_planning' IS NOT NULL").limit(5).each do |chat|
        puts "  - Chat #{chat.id}: #{chat.planning_context.present? ? 'has planning_context' : 'MISSING planning_context'}"
      end
    else
      puts "✓ No pending metadata to migrate"
    end
  end

  desc "Rollback: Clear migrated planning contexts"
  task rollback: :environment do
    puts "Rolling back planning contexts that were migrated from chat metadata..."

    deleted_count = 0

    PlanningContext.where("metadata->>'migrated_from_chat_metadata' = 'true'").find_each do |context|
      if context.destroy
        deleted_count += 1
        puts "  ✓ Deleted planning_context #{context.id}"
      else
        puts "  ✗ Failed to delete planning_context #{context.id}"
      end
    end

    puts ""
    puts "Rollback complete! Deleted #{deleted_count} migrated planning contexts"
  end

  desc "Audit: Check for data integrity"
  task audit: :environment do
    puts "Auditing planning context data integrity..."

    issues = []

    PlanningContext.find_each do |context|
      # Check required associations
      unless context.user.present?
        issues << "PlanningContext #{context.id}: Missing user"
      end

      unless context.chat.present?
        issues << "PlanningContext #{context.id}: Missing chat"
      end

      unless context.organization.present?
        issues << "PlanningContext #{context.id}: Missing organization"
      end

      # Check state validity
      valid_states = %w[initial pre_creation refinement resource_creation completed]
      unless valid_states.include?(context.state)
        issues << "PlanningContext #{context.id}: Invalid state '#{context.state}'"
      end

      # Check status validity
      valid_statuses = %w[pending analyzing awaiting_user_input processing complete error]
      unless valid_statuses.include?(context.status)
        issues << "PlanningContext #{context.id}: Invalid status '#{context.status}'"
      end

      # Check if complex contexts have questions or items
      if context.is_complex && context.pre_creation_questions.blank? && context.hierarchical_items.blank?
        issues << "PlanningContext #{context.id}: Complex but has no questions or items"
      end

      # Check if completed contexts have items
      if context.state == "completed" && context.hierarchical_items.blank?
        issues << "PlanningContext #{context.id}: Completed but has no hierarchical items"
      end
    end

    if issues.empty?
      puts "✓ No data integrity issues found!"
    else
      puts "✗ Found #{issues.length} data integrity issue(s):"
      issues.each { |issue| puts "  - #{issue}" }
    end
  end
end
