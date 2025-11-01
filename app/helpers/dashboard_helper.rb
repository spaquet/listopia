# app/helpers/dashboard_helper.rb
module DashboardHelper
  # Adaptive dashboard mode titles
  def adaptive_dashboard_mode_title(mode)
    case mode
    when :recommendations
      "What's Next?"
    when :spotlight
      "List Focus"
    when :action
      "Ready to Act"
    when :nudge
      "Let's Get Going"
    else
      "Dashboard"
    end
  end

  # Adaptive dashboard mode subtitles
  def adaptive_dashboard_mode_subtitle(mode)
    case mode
    when :recommendations
      "Smart recommendations based on your activity"
    when :spotlight
      "Deep dive into this list"
    when :action
      "Suggested actions you can take right now"
    when :nudge
      "Time to get back on track"
    else
      "Your personalized dashboard"
    end
  end

  # Badge styling based on mode
  def mode_badge_class(mode)
    case mode
    when :recommendations
      "bg-blue-100 text-blue-800"
    when :spotlight
      "bg-purple-100 text-purple-800"
    when :action
      "bg-green-100 text-green-800"
    when :nudge
      "bg-orange-100 text-orange-800"
    else
      "bg-gray-100 text-gray-800"
    end
  end

  # Gradient background for recommendations based on score
  def recommendation_gradient(score)
    case score
    when 100..Float::INFINITY
      "from-red-50 to-orange-50 border-l-4 border-red-500"
    when 50..100
      "from-yellow-50 to-amber-50 border-l-4 border-yellow-500"
    when 25..50
      "from-blue-50 to-indigo-50 border-l-4 border-blue-500"
    else
      "from-gray-50 to-gray-100"
    end
  end

  # Format time for display
  def time_ago_in_words_or_date(date)
    return "" unless date

    days_ago = ((Time.current - date) / 1.day).round

    case days_ago
    when 0
      "Today"
    when 1
      "Yesterday"
    when 2..6
      "#{days_ago} days ago"
    when 7..30
      "#{(days_ago / 7).round} weeks ago"
    else
      date.strftime("%b %d, %Y")
    end
  end

  # Format future dates
  def time_until_words(date)
    return "" unless date

    days_until = ((date - Date.current).to_i)

    case days_until
    when 0
      "Today"
    when 1
      "Tomorrow"
    when 2..6
      "In #{days_until} days"
    when 7..30
      "In #{(days_until / 7).round} weeks"
    else
      date.strftime("%b %d, %Y")
    end
  end
end
