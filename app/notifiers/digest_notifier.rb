# app/notifiers/digest_notifier.rb
class DigestNotifier < ApplicationNotifier
  def notification_type
    "digest"
  end

  def title
    "#{frequency_label} digest: #{summary_title}"
  end

  def message
    "You have #{activity_summary}. Review your activity summary to catch up."
  end

  def icon
    "inbox"
  end

  def url
    dashboard_path
  end

  private

  def frequency_label
    case params[:frequency]
    when "daily"
      "Daily"
    when "weekly"
      "Weekly"
    else
      "Activity"
    end
  end

  def summary_title
    item_count = params[:item_count] || 0
    comment_count = params[:comment_count] || 0
    status_count = params[:status_count] || 0

    items = []
    items << "#{item_count} items" if item_count > 0
    items << "#{comment_count} comments" if comment_count > 0
    items << "#{status_count} status changes" if status_count > 0

    items.empty? ? "Activity Update" : items.join(", ")
  end

  def activity_summary
    item_count = params[:item_count] || 0
    comment_count = params[:comment_count] || 0
    status_count = params[:status_count] || 0

    items = []
    items << "#{item_count} new/updated items" if item_count > 0
    items << "#{comment_count} new comments" if comment_count > 0
    items << "#{status_count} status changes" if status_count > 0

    items.empty? ? "no significant activity" : items.join(", ")
  end
end
