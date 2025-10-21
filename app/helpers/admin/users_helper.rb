# app/helpers/admin/users_helper.rb
module Admin::UsersHelper
  def user_status_badge(user)
    status_config = {
      "active" => { bg: "bg-green-100", text: "text-green-800", label: "Active" },
      "suspended" => { bg: "bg-red-100", text: "text-red-800", label: "Suspended" },
      "inactive" => { bg: "bg-gray-100", text: "text-gray-800", label: "Inactive" }
    }

    config = status_config[user.status] || status_config["inactive"]

    content_tag :span, class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium #{config[:bg]} #{config[:text]}" do
      concat content_tag(:span, nil, class: "w-2 h-2 mr-1.5 #{config[:bg]} rounded-full")
      concat config[:label]
    end
  end

  def user_role_badge(user)
    if user.admin?
      content_tag :span, "Admin",
        class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-purple-100 text-purple-800"
    else
      content_tag :span, "User",
        class: "inline-flex items-center px-2.5 py-0.5 rounded-full text-xs font-medium bg-gray-100 text-gray-800"
    end
  end

  def email_verification_icon(user)
    if user.email_verified?
      content_tag :svg, nil,
        class: "w-5 h-5 text-green-500",
        fill: "currentColor",
        viewBox: "0 0 20 20" do
        concat tag.path(
          "fill-rule": "evenodd",
          "d": "M10 18a8 8 0 100-16 8 8 0 000 16zm3.707-9.293a1 1 0 00-1.414-1.414L9 10.586 7.707 9.293a1 1 0 00-1.414 1.414l2 2a1 1 0 001.414 0l4-4z",
          "clip-rule": "evenodd"
        )
      end
    else
      content_tag :svg, nil,
        class: "w-5 h-5 text-gray-300",
        fill: "currentColor",
        viewBox: "0 0 20 20" do
        concat tag.path(
          "fill-rule": "evenodd",
          "d": "M10 18a8 8 0 100-16 8 8 0 000 16zM8.707 7.293a1 1 0 00-1.414 1.414L8.586 10l-1.293 1.293a1 1 0 101.414 1.414L10 11.414l1.293-1.293a1 1 0 101.414-1.414L11.414 10l1.293-1.293a1 1 0 00-1.414-1.414L10 8.586 8.707 7.293z",
          "clip-rule": "evenodd"
        )
      end
    end
  end

  def user_joined_date(user)
    time_ago_in_words(user.created_at)
  end

  def user_avatar_initials(user, size: "w-10 h-10 text-sm")
    initials = user.name.split.map(&:first).join.upcase[0..1]

    content_tag :div, initials,
      class: "#{size} bg-gradient-to-br from-blue-400 to-blue-600 text-white rounded-full flex items-center justify-center font-semibold flex-shrink-0",
      title: user.name
  end

  def suspend_toggle_button(user)
    if user.active?
      button_to "Suspend", toggle_status_admin_user_path(user), method: :patch,
        class: "inline-flex items-center px-3 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500",
        data: { turbo_method: :patch }
    elsif user.suspended?
      button_to "Reactivate", toggle_status_admin_user_path(user), method: :patch,
        class: "inline-flex items-center px-3 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500",
        data: { turbo_method: :patch }
    end
  end

  def admin_toggle_button(user)
    if user.admin?
      button_to "Remove Admin", toggle_admin_admin_user_path(user), method: :patch,
        class: "inline-flex items-center px-3 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500",
        data: { turbo_method: :patch }
    else
      button_to "Make Admin", toggle_admin_admin_user_path(user), method: :patch,
        class: "inline-flex items-center px-3 py-2 border border-gray-300 rounded-md shadow-sm text-sm font-medium text-gray-700 bg-white hover:bg-gray-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-blue-500",
        data: { turbo_method: :patch }
    end
  end

  def delete_user_button(user, current_user)
    return unless user != current_user

    button_to "Delete", admin_user_path(user), method: :delete,
      class: "inline-flex items-center px-3 py-2 border border-red-300 rounded-md shadow-sm text-sm font-medium text-red-700 bg-white hover:bg-red-50 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-red-500",
      data: { turbo_confirm: "Are you sure? This action cannot be undone." }
  end

  def filter_url(new_filters)
    admin_users_url(admin_users_params.merge(new_filters))
  end

  private

  def admin_users_params
    params.slice(:query, :status, :role, :verified, :sort_by).permit!
  end
end
