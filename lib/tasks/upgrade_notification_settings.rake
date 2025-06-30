# lib/tasks/upgrade_notification_settings.rake
#
# == Task: users:upgrade_notification_settings
#
# === Purpose
# This Rake task upgrades existing users in the system by creating default NotificationSettings
# records for those who do not have them. It is designed to be used after adding the
# `notification_settings` table to the database via a migration, ensuring all users are
# migrated to the new notification settings configuration.
#
# === When to Use
# Run this task:
# - After deploying a database migration that adds the `notification_settings` table.
# - When upgrading a legacy system to include notification settings for all existing users.
# - As a one-time data migration to populate NotificationSettings for users who lack them.
# - Do NOT run this task repeatedly unless you need to re-process users (it only affects users
#   without settings, so it’s safe to run multiple times, but unnecessary runs are redundant).
#
# === Prerequisites
# - The `notification_settings` table must exist in the database (via migration).
# - The `User` model must have a `has_one` or `belongs_to` association with `NotificationSettings`.
# - The `NotificationSettings` model must have the following attributes:
#   - email_notifications (boolean)
#   - sms_notifications (boolean)
#   - push_notifications (boolean)
#   - collaboration_notifications (boolean)
#   - list_activity_notifications (boolean)
#   - item_activity_notifications (boolean)
#   - status_change_notifications (boolean)
#   - notification_frequency (string, e.g., 'immediate')
#   - timezone (string, e.g., 'UTC')
# - Ensure database migrations are applied (`bin/rails db:migrate`).
# - Back up the database before running in production to prevent data loss.
#
# === Usage
# Run the task from the root of your Rails application:
#   bin/rails users:upgrade_notification_settings
#
# To specify a custom batch size for processing users (default: 500):
#   bin/rails users:upgrade_notification_settings BATCH_SIZE=200
#
# === Batch Processing
# - The task processes users in batches to optimize performance for large datasets.
# - Default batch size is 500, but can be customized via the BATCH_SIZE environment variable.
# - Smaller batch sizes reduce memory usage but may increase total runtime due to more queries.
# - Larger batch sizes may improve runtime but increase memory and database load.
# - Tune the batch size based on your database server’s performance (e.g., 100–1000).
#
# === Example Output
#   Starting upgrade process for user notification settings...
#   Using batch size: 500
#   Found 5000 users without notification settings
#   Processing batch 1/10 (500 users)...
#   Created notification settings for user1@example.com
#   Created notification settings for user2@example.com
#   Failed to create settings for user3@example.com: Validation failed: Notification frequency is invalid
#   Processing batch 2/10 (500 users)...
#   ...
#   Upgrade complete!
#   Processed 5000 users in 10 batches
#   Successfully upgraded: 4990
#   Failed: 10
#    - user3@example.com: Validation failed: Notification frequency is invalid
#    - user10@example.com: Validation failed: Timezone is invalid
#
# If no users are found:
#   Starting upgrade process for user notification settings...
#   Using batch size: 500
#   Found 0 users without notification settings
#   No action needed: all users already have notification settings.
#
# === Notes
# - The task is idempotent: it only processes users without NotificationSettings, so it won’t
#   create duplicate records.
# - Uses `find_in_batches` for pagination to handle large datasets efficiently.
# - Errors (e.g., validation failures) are caught and logged without halting the task.
# - The task uses the user’s `timezone` if available; otherwise, it defaults to 'UTC'.
# - Test in a development/staging environment before running in production.
# - For large datasets, monitor database performance and adjust BATCH_SIZE as needed.
# - To verify completion, check in the console:
#     User.includes(:notification_settings).where(notification_settings: { id: nil }).count
#   This should return 0 if all users were upgraded successfully.
#

namespace :users do
  desc "Upgrade existing users by creating default notification settings for those without them"
  task upgrade_notification_settings: :environment do
    puts "Starting upgrade process for user notification settings..."

    # Get batch size from environment variable or default to 500
    batch_size = (ENV["BATCH_SIZE"]&.to_i || 500).clamp(1, 10_000)
    puts "Using batch size: #{batch_size}"

    # Find users without notification settings
    users_without_settings = User.left_joins(:notification_settings)
                                .where(notification_settings: { id: nil })

    total_users = users_without_settings.count
    puts "Found #{total_users} users without notification settings"

    # Exit cleanly if no users need processing
    if total_users.zero?
      puts "No action needed: all users already have notification settings."
      next
    end

    # Calculate total batches for reporting
    total_batches = (total_users.to_f / batch_size).ceil

    # Track successes and failures
    successes = 0
    failures = []
    batch_number = 0

    # Process users in batches
    users_without_settings.find_in_batches(batch_size: batch_size) do |batch|
      batch_number += 1
      puts "Processing batch #{batch_number}/#{total_batches} (#{batch.size} users)..."

      batch.each do |user|
        begin
          user.create_notification_settings!(
            email_notifications: true,
            sms_notifications: false,
            push_notifications: true,
            collaboration_notifications: true,
            list_activity_notifications: true,
            item_activity_notifications: true,
            status_change_notifications: true,
            notification_frequency: "immediate",
            timezone: user.timezone || "UTC" # Fallback to user's timezone if available
          )
          successes += 1
          puts "Created notification settings for #{user.email}"
        rescue ActiveRecord::RecordInvalid => e
          failures << { email: user.email, error: e.message }
          puts "Failed to create settings for #{user.email}: #{e.message}"
        end
      end
    end

    # Summary
    puts "\nUpgrade complete!"
    puts "Processed #{total_users} users in #{total_batches} batches"
    puts "Successfully upgraded: #{successes}"
    puts "Failed: #{failures.count}"
    failures.each do |failure|
      puts " - #{failure[:email]}: #{failure[:error]}"
    end
  end
end
