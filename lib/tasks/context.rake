# lib/tasks/context.rake - Rake tasks for context management
namespace :context do
  desc "Clean up old conversation contexts"
  task cleanup: :environment do
    puts "Starting conversation context cleanup..."
    result = ConversationContextManager.cleanup_expired_contexts!
    puts "Cleanup completed: #{result[:total]} contexts removed"
  end

  desc "Show context statistics"
  task stats: :environment do
    total_contexts = ConversationContext.count
    active_contexts = ConversationContext.active.count
    users_with_contexts = ConversationContext.distinct.count(:user_id)

    puts "Conversation Context Statistics:"
    puts "- Total contexts: #{total_contexts}"
    puts "- Active contexts: #{active_contexts}"
    puts "- Users with contexts: #{users_with_contexts}"
    puts "- Average contexts per user: #{total_contexts / [ users_with_contexts, 1 ].max}"

    # Show breakdown by action
    puts "\nBreakdown by action:"
    ConversationContext.group(:action).count.each do |action, count|
      puts "- #{action}: #{count}"
    end

    # Show breakdown by entity type
    puts "\nBreakdown by entity type:"
    ConversationContext.group(:entity_type).count.each do |type, count|
      puts "- #{type}: #{count}"
    end
  end

  desc "Clean up contexts for deleted entities"
  task cleanup_deleted_entities: :environment do
    puts "Cleaning up contexts for deleted entities..."

    # This would be handled by the cleanup job, but can be run manually
    deleted_count = 0

    ConversationContext.find_each do |context|
      entity_class = context.entity_type.constantize rescue nil
      next unless entity_class

      unless entity_class.exists?(context.entity_id)
        context.destroy
        deleted_count += 1
      end
    end

    puts "Removed #{deleted_count} contexts for deleted entities"
  end

  desc "Show recent activity for a user"
  task :user_activity, [ :user_id ] => :environment do |t, args|
    user = User.find(args[:user_id])
    puts "Recent activity for #{user.name} (#{user.email}):"

    user.conversation_contexts.recent.limit(20).each do |context|
      entity_info = "#{context.entity_type}:#{context.entity_data['title'] || context.entity_id}"
      puts "- #{context.created_at.strftime('%m/%d %H:%M')} #{context.action} #{entity_info}"
    end
  end
end
