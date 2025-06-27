# app/helpers/item_types_helper.rb
module ItemTypesHelper
  # Centralized configuration for all item types
  ITEM_TYPE_CONFIG = {
    # Core Planning Types
    task: {
      label: 'Task',
      description: 'Basic actionable item',
      icon_path: 'M9 12l2 2 4-4m6 2a9 9 0 11-18 0 9 9 0 0118 0z',
      color: 'text-blue-600',
      category: :planning,
      supports: {
        completion: true,
        due_date: true,
        assignment: true,
        priority: true
      }
    },
    goal: {
      label: 'Goal',
      description: 'Objective or target to achieve',
      icon_path: 'M9 12l2 2 4-4m5.618-4.016A11.955 11.955 0 0112 2.944a11.955 11.955 0 01-8.618 3.04A12.02 12.02 0 003 9c0 5.591 3.824 10.29 9 11.622 5.176-1.332 9-6.03 9-11.622 0-1.042-.133-2.052-.382-3.016z',
      color: 'text-purple-600',
      category: :planning,
      supports: {
        completion: true,
        due_date: true,
        assignment: true,
        priority: true
      }
    },
    milestone: {
      label: 'Milestone',
      description: 'Key deadline or achievement',
      icon_path: 'M16.707 5.293a1 1 0 010 1.414l-8 8a1 1 0 01-1.414 0l-4-4a1 1 0 011.414-1.414L8 12.586l7.293-7.293a1 1 0 011.414 0z',
      color: 'text-yellow-600',
      category: :planning,
      supports: {
        completion: true,
        due_date: true,
        assignment: true,
        priority: true
      }
    },
    action_item: {
      label: 'Action Item',
      description: 'Specific next action to take',
      icon_path: 'M13 10V3L4 14h7v7l9-11h-7z',
      color: 'text-orange-600',
      category: :planning,
      supports: {
        completion: true,
        due_date: true,
        assignment: true,
        priority: true
      }
    },
    waiting_for: {
      label: 'Waiting For',
      description: 'Blocked item awaiting others',
      icon_path: 'M12 8v4l3 3m6-3a9 9 0 11-18 0 9 9 0 0118 0z',
      color: 'text-gray-600',
      category: :planning,
      supports: {
        completion: true,
        due_date: true,
        assignment: false,
        priority: true
      }
    },
    reminder: {
      label: 'Reminder',
      description: 'Time-based notification',
      icon_path: 'M15 17h5l-5 5v-5zM4 1h8l6 6v4h-1V8h-5V3H5v16h6v1H4V1z',
      color: 'text-red-600',
      category: :planning,
      supports: {
        completion: false,
        due_date: true,
        assignment: false,
        priority: false
      }
    },

    # Knowledge & Ideas
    idea: {
      label: 'Idea',
      description: 'Brainstorm or concept',
      icon_path: 'M9.663 17h4.673M12 3v1m6.364 1.636l-.707.707M21 12h-1M4 12H3m3.343-5.657l-.707-.707m2.828 9.9a5 5 0 117.072 0l-.548.547A3.374 3.374 0 0014 18.469V19a2 2 0 11-4 0v-.531c0-.895-.356-1.754-.988-2.386l-.548-.547z',
      color: 'text-yellow-500',
      category: :knowledge,
      supports: {
        completion: false,
        due_date: false,
        assignment: false,
        priority: false
      }
    },
    note: {
      label: 'Note',
      description: 'Information or documentation',
      icon_path: 'M11 5H6a2 2 0 00-2 2v11a2 2 0 002 2h11a2 2 0 002-2v-5m-1.414-9.414a2 2 0 112.828 2.828L11.828 15H9v-2.828l8.586-8.586z',
      color: 'text-green-600',
      category: :knowledge,
      supports: {
        completion: false,
        due_date: false,
        assignment: false,
        priority: false
      }
    },
    reference: {
      label: 'Reference',
      description: 'Link or resource',
      icon_path: 'M13.828 10.172a4 4 0 00-5.656 0l-4 4a4 4 0 105.656 5.656l1.102-1.101m-.758-4.899a4 4 0 005.656 0l4-4a4 4 0 00-5.656-5.656l-1.1 1.1',
      color: 'text-indigo-600',
      category: :knowledge,
      supports: {
        completion: false,
        due_date: false,
        assignment: false,
        priority: false
      }
    },

    # Personal Life Management
    habit: {
      label: 'Habit',
      description: 'Recurring personal development',
      icon_path: 'M4 4v5h.582m15.356 2A8.001 8.001 0 004.582 9m0 0H9m11 11v-5h-.581m0 0a8.003 8.003 0 01-15.357-2m15.357 2H15',
      color: 'text-teal-600',
      category: :personal,
      supports: {
        completion: true,
        due_date: false,
        assignment: false,
        priority: true
      }
    },
    health: {
      label: 'Health',
      description: 'Fitness, medical, wellness',
      icon_path: 'M4.318 6.318a4.5 4.5 0 000 6.364L12 20.364l7.682-7.682a4.5 4.5 0 00-6.364-6.364L12 7.636l-1.318-1.318a4.5 4.5 0 00-6.364 0z',
      color: 'text-pink-600',
      category: :personal,
      supports: {
        completion: true,
        due_date: true,
        assignment: false,
        priority: true
      }
    },
    learning: {
      label: 'Learning',
      description: 'Books, courses, skills',
      icon_path: 'M12 6.253v13m0-13C10.832 5.477 9.246 5 7.5 5S4.168 5.477 3 6.253v13C4.168 18.477 5.754 18 7.5 18s3.332.477 4.5 1.253m0-13C13.168 5.477 14.754 5 16.5 5c1.747 0 3.332.477 4.5 1.253v13C19.832 18.477 18.246 18 16.5 18c-1.746 0-3.332.477-4.5 1.253',
      color: 'text-blue-700',
      category: :personal,
      supports: {
        completion: true,
        due_date: true,
        assignment: false,
        priority: true
      }
    },
    travel: {
      label: 'Travel',
      description: 'Trips and vacation planning',
      icon_path: 'M3 21v-4m0 0V5a2 2 0 012-2h6.5l1 1H21l-3 6 3 6h-8.5l-1-1H5a2 2 0 00-2 2zm9-13.5V9',
      color: 'text-sky-600',
      category: :personal,
      supports: {
        completion: true,
        due_date: true,
        assignment: false,
        priority: true
      }
    },
    shopping: {
      label: 'Shopping',
      description: 'Purchases and errands',
      icon_path: 'M16 11V7a4 4 0 00-8 0v4M5 9h14l-1 12H6L5 9z',
      color: 'text-emerald-600',
      category: :personal,
      supports: {
        completion: true,
        due_date: true,
        assignment: false,
        priority: true
      }
    },
    home: {
      label: 'Home',
      description: 'Household tasks and improvements',
      icon_path: 'M3 12l2-2m0 0l7-7 7 7M5 10v10a1 1 0 001 1h3m10-11l2 2m-2-2v10a1 1 0 01-1 1h-3m-6 0a1 1 0 001-1v-4a1 1 0 011-1h2a1 1 0 011 1v4a1 1 0 001 1m-6 0h6',
      color: 'text-amber-700',
      category: :personal,
      supports: {
        completion: true,
        due_date: true,
        assignment: true,
        priority: true
      }
    },
    finance: {
      label: 'Finance',
      description: 'Budget, bills, investments',
      icon_path: 'M12 8c-1.657 0-3 .895-3 2s1.343 2 3 2 3 .895 3 2-1.343 2-3 2m0-8c1.11 0 2.08.402 2.599 1M12 8V7m0 1v8m0 0v1m0-1c-1.11 0-2.08-.402-2.599-1M21 12a9 9 0 11-18 0 9 9 0 0118 0z',
      color: 'text-green-700',
      category: :personal,
      supports: {
        completion: true,
        due_date: true,
        assignment: false,
        priority: true
      }
    },
    social: {
      label: 'Social',
      description: 'Events, gatherings, relationships',
      icon_path: 'M17 20h5v-2a3 3 0 00-5.356-1.857M17 20H7m10 0v-2c0-.656-.126-1.283-.356-1.857M7 20H2v-2a3 3 0 015.356-1.857M7 20v-2c0-.656.126-1.283.356-1.857m0 0a5.002 5.002 0 019.288 0M15 7a3 3 0 11-6 0 3 3 0 016 0zm6 3a2 2 0 11-4 0 2 2 0 014 0zM7 10a2 2 0 11-4 0 2 2 0 014 0z',
      color: 'text-purple-700',
      category: :personal,
      supports: {
        completion: true,
        due_date: true,
        assignment: false,
        priority: true
      }
    },
    entertainment: {
      label: 'Entertainment',
      description: 'Movies, shows, games, hobbies',
      icon_path: 'M7 4V2a1 1 0 011-1h8a1 1 0 011 1v2h4a1 1 0 011 1v14a1 1 0 01-1 1H3a1 1 0 01-1-1V5a1 1 0 011-1h4zM9 3v1h6V3H9zm11 2H4v12h16V5z',
      color: 'text-rose-600',
      category: :personal,
      supports: {
        completion: true,
        due_date: false,
        assignment: false,
        priority: false
      }
    }
  }.freeze

  # Helper methods for easy access
  def item_type_config(type)
    ITEM_TYPE_CONFIG[type.to_sym] || ITEM_TYPE_CONFIG[:task]
  end

  def item_type_label(type)
    item_type_config(type)[:label]
  end

  def item_type_description(type)
    item_type_config(type)[:description]
  end

  def item_type_icon_svg(type, css_class: 'w-5 h-5')
    config = item_type_config(type)
    content_tag :svg,
                fill: 'none',
                stroke: 'currentColor',
                viewBox: '0 0 24 24',
                class: "#{css_class} #{config[:color]}" do
      content_tag :path, '',
                  stroke_linecap: 'round',
                  stroke_linejoin: 'round',
                  stroke_width: '2',
                  d: config[:icon_path]
    end
  end

  def item_type_category(type)
    item_type_config(type)[:category]
  end

  def item_type_supports?(type, feature)
    item_type_config(type)[:supports][feature.to_sym] || false
  end

  # Options for select dropdowns
  def item_type_options_for_select(grouped: false)
    if grouped
      grouped_options = {
        'Planning' => [],
        'Knowledge' => [],
        'Personal' => []
      }

      ITEM_TYPE_CONFIG.each do |key, config|
        group_name = case config[:category]
                    when :planning then 'Planning'
                    when :knowledge then 'Knowledge'
                    when :personal then 'Personal'
                    end
        grouped_options[group_name] << [config[:label], key.to_s]
      end

      grouped_options.select { |_, options| options.any? }
    else
      ITEM_TYPE_CONFIG.map { |key, config| [config[:label], key.to_s] }
    end
  end

  # For custom select components
  def item_type_options_with_icons
    ITEM_TYPE_CONFIG.map do |key, config|
      {
        value: key.to_s,
        label: config[:label],
        description: config[:description],
        icon_path: config[:icon_path],
        color: config[:color],
        category: config[:category]
      }
    end
  end

  # Category-specific helpers
  def planning_item_types
    ITEM_TYPE_CONFIG.select { |_, config| config[:category] == :planning }.keys
  end

  def knowledge_item_types
    ITEM_TYPE_CONFIG.select { |_, config| config[:category] == :knowledge }.keys
  end

  def personal_item_types
    ITEM_TYPE_CONFIG.select { |_, config| config[:category] == :personal }.keys
  end
end
