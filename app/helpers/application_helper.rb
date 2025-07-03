# app/helpers/application_helper.rb
module ApplicationHelper
  # Format user-friendly timestamps
  def time_ago_in_words_or_date(time)
    return "" unless time

    if time > 1.week.ago
      time_ago_in_words(time) + " ago"
    else
      time.strftime("%B %d, %Y")
    end
  end

  # Generate avatar initials for users without avatar images
  def user_avatar_initials(user, size: "w-8 h-8")
    return "" unless user&.name

    initials = user.name.split.map(&:first).join.upcase[0..1]

    content_tag :div, initials,
                class: "#{size} bg-blue-500 text-white rounded-full flex items-center justify-center text-sm font-medium"
  end

  # Navigation link helper for active states
  def nav_link_class(path)
    base_classes = "text-gray-700 hover:text-blue-600 px-3 py-2 rounded-md text-sm font-medium transition-colors duration-200 flex items-center"
    active_classes = "bg-blue-50 text-blue-600"

    if current_page?(path)
      "#{base_classes} #{active_classes}"
    else
      base_classes
    end
  end

  # Status badge helper for lists
  def list_status_badge(list)
    color_class = case list.status
    when "draft" then "bg-gray-100 text-gray-800"
    when "active" then "bg-green-100 text-green-800"
    when "completed" then "bg-blue-100 text-blue-800"
    when "archived" then "bg-yellow-100 text-yellow-800"
    else "bg-gray-100 text-gray-800"
    end

    content_tag :span, list.status.titleize,
                class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{color_class}"
  end

  # Priority badge for list items
  def priority_badge(item)
    color_class = case item.priority
    when "low" then "bg-gray-100 text-gray-600"
    when "medium" then "bg-yellow-100 text-yellow-700"
    when "high" then "bg-orange-100 text-orange-700"
    when "urgent" then "bg-red-100 text-red-700"
    else "bg-gray-100 text-gray-600"
    end

    content_tag :span, item.priority.titleize,
                class: "inline-flex items-center px-1.5 py-0.5 rounded text-xs font-medium #{color_class}"
  end

  # Progress bar helper
  def progress_bar(percentage, color: "blue")
    content_tag :div, class: "w-full bg-gray-200 rounded-full h-2" do
      content_tag :div, "",
                  class: "bg-#{color}-600 h-2 rounded-full transition-all duration-300",
                  style: "width: #{percentage}%"
    end
  end

  # Format due date with appropriate styling
  def format_due_date(date)
    return "" unless date

    if date < Time.current
      content_tag :span, date.strftime("%b %d"), class: "text-red-600 font-medium"
    elsif date < 1.day.from_now
      content_tag :span, "Due today", class: "text-orange-600 font-medium"
    elsif date < 3.days.from_now
      content_tag :span, date.strftime("%b %d"), class: "text-yellow-600"
    else
      content_tag :span, date.strftime("%b %d"), class: "text-gray-600"
    end
  end

  # Check if current page matches given path
  def current_page?(path)
    request.path == path
  end

  # Generate breadcrumbs - FIXED VERSION
  def breadcrumbs(*crumbs)
    content_tag :nav, class: "flex", aria: { label: "Breadcrumb" } do
      content_tag :ol, class: "inline-flex items-center space-x-1 md:space-x-3" do
        crumb_items = crumbs.map.with_index do |crumb, index|
          if index == crumbs.length - 1
            # Last crumb (current page)
            content_tag :li, class: "inline-flex items-center" do
              content_tag :span, crumb[:text], class: "ml-1 text-gray-500 text-sm font-medium"
            end
          else
            # Regular crumb with separator
            content_tag :li, class: "inline-flex items-center" do
              link_content = link_to crumb[:path], class: "inline-flex items-center text-sm font-medium text-gray-700 hover:text-blue-600" do
                crumb[:text]
              end

              separator = content_tag(:svg, class: "w-6 h-6 text-gray-400 ml-1", fill: "currentColor", viewBox: "0 0 20 20") do
                content_tag :path, "", 'fill-rule': "evenodd",
                           d: "M7.293 14.707a1 1 0 010-1.414L10.586 10 7.293 6.707a1 1 0 011.414-1.414l4 4a1 1 0 010 1.414l-4 4a1 1 0 01-1.414 0z",
                           'clip-rule': "evenodd"
              end

              link_content + separator
            end
          end
        end

        crumb_items.join.html_safe
      end
    end
  end

  # Icon helper for different contexts
  def icon(name, options = {})
    size = options[:size] || "w-5 h-5"
    css_class = "#{size} #{options[:class]}"

    icons = {
      "check-circle" => '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z"></path>',
      "users" => '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4.354a4 4 0 110 5.292M15 21H3v-1a6 6 0 0112 0v1zm0 0h6v-1a6 6 0 00-9-5.197m13.5-9a2.5 2.5 0 11-5 0 2.5 2.5 0 015 0z"></path>',
      "lightning-bolt" => '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M13 10V3L4 14h7v7l9-11h-7z"></path>',
      "plus" => '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"></path>',
      "edit" => '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z"></path>',
      "share" => '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M8.684 13.342C8.886 12.938 9 12.482 9 12c0-.482-.114-.938-.316-1.342m0 2.684a3 3 0 110-2.684m0 2.684l6.632 3.316m-6.632-6l6.632-3.316m0 0a3 3 0 105.367-2.684 3 3 0 00-5.367 2.684zm0 9.316a3 3 0 105.367 2.684 3 3 0 00-5.367-2.684z"></path>',
      "delete" => '<path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M19 7l-.867 12.142A2 2 0 0116.138 21H7.862a2 2 0 01-1.995-1.858L5 7m5 4v6m4-6v6m1-10V4a1 1 0 00-1-1h-4a1 1 0 00-1 1v3M4 7h16"></path>'
    }

    content_tag :svg, class: css_class, fill: "none", stroke: "currentColor", viewBox: "0 0 24 24" do
      icons[name]&.html_safe || ""
    end
  end

  # Helper to check if user can perform action on resource
  def can?(action, resource)
    case action.to_sym
    when :edit, :update, :destroy
      if resource.is_a?(List)
        resource.owner == current_user || resource.collaboratable_by?(current_user)
      elsif resource.is_a?(ListItem)
        resource.list.owner == current_user || resource.editable_by?(current_user)
      else
        false
      end
    when :read, :show
      if resource.is_a?(List)
        resource.readable_by?(current_user)
      elsif resource.is_a?(ListItem)
        resource.list.readable_by?(current_user)
      else
        false
      end
    else
      false
    end
  end

  # Generate a random gradient class for visual variety
  def random_gradient
    gradients = [
      "from-blue-600 to-purple-600",
      "from-green-600 to-blue-600",
      "from-purple-600 to-pink-600",
      "from-yellow-600 to-red-600",
      "from-indigo-600 to-purple-600",
      "from-pink-600 to-rose-600"
    ]

    gradients.sample
  end

  # Helper method to get updated dashboard data for a user
  # This is used in turbo stream templates to update dashboard sections
  def dashboard_data_for_user(user)
    {
      my_lists: user.lists.includes(:list_items, :collaborators).order(updated_at: :desc).limit(10),
      collaborated_lists: user.collaborated_lists.includes(:owner, :list_items).order(updated_at: :desc).limit(10),
      recent_items: ListItem.joins(:list).where(list: user.accessible_lists).order(updated_at: :desc).limit(20),
      stats: calculate_dashboard_stats_for_user(user)
    }
  end

  # Calculate statistics for dashboard display
  def calculate_dashboard_stats_for_user(user)
    accessible_lists = user.accessible_lists

    {
      total_lists: accessible_lists.count,
      active_lists: accessible_lists.status_active.count,
      completed_lists: accessible_lists.status_completed.count,
      total_items: ListItem.joins(:list).where(list: accessible_lists).count,
      completed_items: ListItem.joins(:list).where(list: accessible_lists, completed: true).count,
      overdue_items: ListItem.joins(:list).where(list: accessible_lists)
                            .where("due_date < ? AND completed = false", Time.current).count
    }
  end
end
