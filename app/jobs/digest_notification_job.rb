# app/jobs/digest_notification_job.rb
class DigestNotificationJob < ApplicationJob
  queue_as :default

  # Run daily at 9 AM
  def self.schedule_daily
    set(wait_until: next_run_time(:daily)).perform_later(:daily)
  end

  # Run weekly on Mondays at 9 AM
  def self.schedule_weekly
    set(wait_until: next_run_time(:weekly)).perform_later(:weekly)
  end

  def perform(frequency = :daily)
    case frequency
    when :daily
      send_daily_digests
      schedule_next_daily
    when :weekly
      send_weekly_digests
      schedule_next_weekly
    end
  end

  private

  def send_daily_digests
    User.find_each do |user|
      next unless user.wants_digest_notifications?(:daily)

      digest_data = compile_daily_digest(user)
      next if digest_data[:item_count].zero? && digest_data[:comment_count].zero? && digest_data[:status_count].zero?

      send_digest(user, :daily, digest_data)
    end
  end

  def send_weekly_digests
    User.find_each do |user|
      next unless user.wants_digest_notifications?(:weekly)

      digest_data = compile_weekly_digest(user)
      next if digest_data[:item_count].zero? && digest_data[:comment_count].zero? && digest_data[:status_count].zero?

      send_digest(user, :weekly, digest_data)
    end
  end

  def compile_daily_digest(user)
    time_range = 1.day.ago..Time.current

    # Get notifications from the past day
    notifications = user.notifications.where(created_at: time_range)

    item_activities = notifications.where(event: { notification_type: [ "item_activity", "item_assignment", "item_completion" ] }).count
    comments = notifications.where(event: { notification_type: "item_comment" }).count
    status_changes = notifications.where(event: { notification_type: "status_change" }).count

    {
      item_count: item_activities,
      comment_count: comments,
      status_count: status_changes,
      frequency: :daily,
      summary_items: build_summary_items(notifications, 5)
    }
  end

  def compile_weekly_digest(user)
    time_range = 1.week.ago..Time.current

    # Get notifications from the past week
    notifications = user.notifications.where(created_at: time_range)

    item_activities = notifications.where(event: { notification_type: [ "item_activity", "item_assignment", "item_completion" ] }).count
    comments = notifications.where(event: { notification_type: "item_comment" }).count
    status_changes = notifications.where(event: { notification_type: "status_change" }).count

    {
      item_count: item_activities,
      comment_count: comments,
      status_count: status_changes,
      frequency: :weekly,
      summary_items: build_summary_items(notifications, 10)
    }
  end

  def build_summary_items(notifications, limit = 5)
    notifications.recent.limit(limit).map do |notification|
      "#{notification.title}: #{notification.message}"
    end
  end

  def send_digest(user, frequency, digest_data)
    DigestNotifier.with(
      actor_id: user.id,
      frequency: frequency.to_s,
      item_count: digest_data[:item_count],
      comment_count: digest_data[:comment_count],
      status_count: digest_data[:status_count],
      summary_items: digest_data[:summary_items]
    ).deliver([ user ])
  end

  def self.next_run_time(frequency)
    now = Time.current

    case frequency
    when :daily
      # Next 9 AM
      next_run = now.tomorrow.beginning_of_day + 9.hours
      next_run = now + 9.hours if now.hour < 9
      next_run
    when :weekly
      # Next Monday at 9 AM
      days_until_monday = (1 - now.wday) % 7
      days_until_monday = 7 if days_until_monday == 0 && now.hour >= 9
      next_run = now.advance(days: days_until_monday).beginning_of_day + 9.hours
      next_run = now + 9.hours if days_until_monday == 0 && now.hour < 9
      next_run
    end
  end

  def schedule_next_daily
    set(wait_until: self.class.next_run_time(:daily)).perform_later(:daily)
  end

  def schedule_next_weekly
    set(wait_until: self.class.next_run_time(:weekly)).perform_later(:weekly)
  end
end
