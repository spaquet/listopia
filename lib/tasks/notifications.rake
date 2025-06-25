# Create a rake task for cleaning up old notifications
# lib/tasks/notifications.rake
namespace :notifications do
  desc "Clean up old notifications (older than 90 days)"
  task cleanup: :environment do
    cutoff_date = 90.days.ago

    old_notifications = Noticed::Notification.where("created_at < ?", cutoff_date)
    count = old_notifications.count

    puts "Cleaning up #{count} notifications older than #{cutoff_date.strftime('%Y-%m-%d')}"

    old_notifications.delete_all

    puts "Cleanup completed. #{count} notifications removed."
  end

  desc "Mark all notifications as seen for a user"
  task :mark_all_seen, [ :user_email ] => :environment do |t, args|
    if args[:user_email].blank?
      puts "Please provide a user email: rake notifications:mark_all_seen[user@example.com]"
      exit 1
    end

    user = User.find_by(email: args[:user_email])
    if user.nil?
      puts "User with email #{args[:user_email]} not found"
      exit 1
    end

    count = user.notifications.unseen.count
    user.notifications.unseen.mark_as_seen!

    puts "Marked #{count} notifications as seen for #{user.email}"
  end

  desc "Show notification statistics"
  task stats: :environment do
    total = Noticed::Notification.count
    unread = Noticed::Notification.unread.count
    unseen = Noticed::Notification.unseen.count
    today = Noticed::Notification.today.count

    puts "Notification Statistics:"
    puts "Total: #{total}"
    puts "Unread: #{unread}"
    puts "Unseen: #{unseen}"
    puts "Today: #{today}"

    # By type
    puts "\nBy Type:"
    Noticed::Event.group(:type).count.each do |type, count|
      puts "  #{type}: #{count}"
    end
  end
end
