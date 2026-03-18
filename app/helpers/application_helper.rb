# app/helpers/application_helper.rb
module ApplicationHelper
  include Pagy::NumericHelpers

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
    elsif date <= Time.current.end_of_day
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

  # Icon tag helper for connector services
  def icon_tag(name, options = {})
    css_class = options[:class] || "w-6 h-6"

    svg_icon = case name
    when "message-square"
      slack_icon
    when "hard-drive"
      google_drive_icon
    when "calendar"
      google_calendar_icon
    else
      default_connector_icon
    end

    svg_icon.html_safe
  end

  private

  def slack_icon
    %(<svg class="w-6 h-6" viewBox="0 0 128 128">
      <path d="M27.255 80.719c0 7.33-5.978 13.317-13.309 13.317C6.616 94.036.63 88.049.63 80.719s5.987-13.317 13.317-13.317h13.309zm6.709 0c0-7.33 5.987-13.317 13.317-13.317s13.317 5.986 13.317 13.317v33.335c0 7.33-5.986 13.317-13.317 13.317-7.33 0-13.317-5.987-13.317-13.317zm0 0" fill="#de1c59"></path>
      <path d="M47.281 27.255c-7.33 0-13.317-5.978-13.317-13.309C33.964 6.616 39.951.63 47.281.63s13.317 5.987 13.317 13.317v13.309zm0 6.709c7.33 0 13.317 5.987 13.317 13.317s-5.986 13.317-13.317 13.317H13.946C6.616 60.598.63 54.612.63 47.281c0-7.33 5.987-13.317 13.317-13.317zm0 0" fill="#35c5f0"></path>
      <path d="M100.745 47.281c0-7.33 5.978-13.317 13.309-13.317 7.33 0 13.317 5.987 13.317 13.317s-5.987 13.317-13.317 13.317h-13.309zm-6.709 0c0 7.33-5.987 13.317-13.317 13.317s-13.317-5.986-13.317-13.317V13.946C67.402 6.616 73.388.63 80.719.63c7.33 0 13.317 5.987 13.317 13.317zm0 0" fill="#2eb57d"></path>
      <path d="M80.719 100.745c7.33 0 13.317 5.978 13.317 13.309 0 7.33-5.987 13.317-13.317 13.317s-13.317-5.987-13.317-13.317v-13.309zm0-6.709c-7.33 0-13.317-5.987-13.317-13.317s5.986-13.317 13.317-13.317h33.335c7.33 0 13.317 5.986 13.317 13.317 0 7.33-5.987 13.317-13.317 13.317zm0 0" fill="#ebb02e"></path>
    </svg>)
  end

  def google_calendar_icon
    %(<svg class="w-6 h-6" xmlns="http://www.w3.org/2000/svg" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M4 7a2 2 0 0 1 2-2h12a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H6a2 2 0 0 1-2-2zm12-4v4M8 3v4m-4 4h16M7 14h.013m2.997 0h.005m2.995 0h.005m3 0h.005m-3.005 3h.005m-6.01 0h.005m2.995 0h.005"/>
    </svg>)
  end

  def google_drive_icon
    %(<svg class="w-6 h-6" xmlns="http://www.w3.org/2000/svg" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <g stroke-linecap="round" stroke-linejoin="round" stroke-width="2">
        <path d="M12 10L6 20l-3-5L9 5z"/>
        <path d="M9 15h12l-3 5H6m9-5L9 5h6l6 10z"/>
      </g>
    </svg>)
  end

  def outlook_icon
    %(<svg class="w-6 h-6" xmlns="http://www.w3.org/2000/svg" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <g stroke-linecap="round" stroke-linejoin="round" stroke-width="2">
        <path d="M4 4h16c1.1 0 2 .9 2 2v12c0 1.1-.9 2-2 2H4c-1.1 0-2-.9-2-2V6c0-1.1.9-2 2-2z"/>
        <path d="M2 6l10 7.5L22 6"/>
      </g>
    </svg>)
  end

  def outlook_calendar_icon
    %(<svg class="w-6 h-6" xmlns="http://www.w3.org/2000/svg" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <g stroke-linecap="round" stroke-linejoin="round" stroke-width="2">
        <path d="M19 3H5c-1.1 0-2 .9-2 2v14c0 1.1.9 2 2 2h14c1.1 0 2-.9 2-2V5c0-1.1-.9-2-2-2z"/>
        <path d="M16 2v4M8 2v4M3 10h18"/>
        <circle cx="8" cy="15" r="1"/>
        <circle cx="12" cy="15" r="1"/>
        <circle cx="16" cy="15" r="1"/>
      </g>
    </svg>)
  end

  def default_connector_icon
    %(<svg class="w-6 h-6" xmlns="http://www.w3.org/2000/svg" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <g stroke-linecap="round" stroke-linejoin="round" stroke-width="2">
        <path d="M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.658 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1"/>
      </g>
    </svg>)
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
      my_lists: user.lists.order(updated_at: :desc).limit(10),
      collaborated_lists: user.collaborated_lists.includes(:owner).order(updated_at: :desc).limit(10),
      recent_items: ListItem.joins(:list).where(list: user.accessible_lists).includes(:list).order(updated_at: :desc).limit(20),
      stats: DashboardStatsService.new(user).call
    }
  end
end
