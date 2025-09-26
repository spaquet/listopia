# lib/tasks/solid_queue.rake - Optional: Manual task management
namespace :solid_queue do
  desc "Start Solid Queue with recurring jobs"
  task start_with_recurring: :environment do
    puts "Starting Solid Queue with recurring job support..."
    system("bundle exec jobs --queues=default,high_priority,low_priority,critical --recurring")
  end

  desc "Show scheduled jobs status"
  task recurring_status: :environment do
    puts "Solid Queue Recurring Jobs Status:"
    # This would depend on your Solid Queue version's API
    # SolidQueue::RecurringTask.all.each do |task|
    #   puts "- #{task.key}: #{task.cron} (#{task.class_name})"
    # end
  end
end
