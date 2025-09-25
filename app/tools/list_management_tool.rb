# app/tools/list_management_tool.rb
class ListManagementTool < RubyLLM::Tool
  description "Manages lists and list items in Listopia. Use this tool for ANY planning, organization, or task management needs."

  param :action,
    type: :string,
    desc: "The action to perform: 'create_list', 'add_item', 'complete_item', 'get_lists', 'get_list_items', 'create_planning_list'"

  param :list_id,
    type: :string,
    desc: "The ID or reference to the list (can be UUID, title, or contextual reference like 'this list')",
    required: false

  param :title,
    type: :string,
    desc: "Title for new lists or items",
    required: false

  param :description,
    type: :string,
    desc: "Description for new lists or items",
    required: false

  param :item_id,
    type: :string,
    desc: "The ID of the item (required for item-specific actions)",
    required: false

  param :planning_context,
    type: :string,
    desc: "Context for planning (e.g., 'event planning', 'travel', 'project management') - helps generate appropriate items",
    required: false

  def initialize(user, context = {})
    @user = user
    @context = context
    @context_manager = ConversationContextManager.new(
      user: @user,
      chat: @user.current_chat,
      current_context: @context
    )

    # Initialize complexity analyzer with user's locale
    if defined?(MultilingualComplexityAnalyzer)
      @complexity_analyzer = MultilingualComplexityAnalyzer.new(
        user: @user,
        context: @context,
        chat: @user.current_chat,
        locale: @user.locale || I18n.locale
      )
    else
      @complexity_analyzer = nil
    end
  end

  def execute(action:, list_id: nil, title: nil, description: nil, item_id: nil, planning_context: nil)
    Rails.logger.info "ListManagementTool executing: #{action} with title: #{title}, list_id: #{list_id}"

    case action
    when "create_list"
      create_list(title, description)
    when "create_planning_list"
      create_planning_list(title, description, planning_context)
    when "add_item"
      add_item(list_id, title, description)
    when "complete_item"
      complete_item(list_id, item_id)
    when "get_lists"
      get_lists
    when "get_list_items"
      get_list_items(list_id)
    else
      {
        success: false,
        error: "Unknown action: #{action}. Available actions: create_list, create_planning_list, add_item, complete_item, get_lists, get_list_items"
      }
    end
  rescue => e
    Rails.logger.error "ListManagementTool error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    {
      success: false,
      error: "Failed to #{action}: #{e.message}"
    }
  end

  private

  def create_planning_list(title, description = nil, planning_context = nil)
    return { success: false, error: "Title is required to create a planning list" } if title.blank?

    # Extract user message from current chat context
    user_message = extract_user_message_from_context || "#{title} #{description}"

    # Analyze complexity before creating
    complexity_analysis = nil
    if @complexity_analyzer
      begin
        complexity_analysis = @complexity_analyzer.analyze_complexity(user_message)
        Rails.logger.info "Complexity analysis: #{complexity_analysis[:complexity_level]} (#{complexity_analysis[:complexity_score]}/10)"
      rescue => e
        Rails.logger.warn "Complexity analysis failed: #{e.message}"
        complexity_analysis = nil
      end
    end

    # Auto-generate description if not provided
    if description.blank?
      description = generate_smart_description(title, planning_context, complexity_analysis)
    end

    # Map context using both existing mapper and complexity analysis
    mapped_context = enhance_planning_context(planning_context, title, complexity_analysis)

    Rails.logger.info "Creating planning list: #{title} with enhanced context: #{mapped_context}"

    begin
      # DECISION: service based on complexity
      service = ListCreationService.new(@user)
      list = service.create_planning_list(
        title: title,
        description: description,
        planning_context: mapped_context
      )

      list.reload
      items_count = list.list_items.count

      Rails.logger.info "Successfully created #{complexity_analysis[:complexity_level]} list #{list.id} with #{items_count} items"

      {
        success: true,
        message: build_success_message_with_complexity(list, complexity_analysis),
        list: serialize_list_with_items(list),
        complexity_insights: extract_user_friendly_insights(complexity_analysis)
      }
    rescue => e
      Rails.logger.error "Failed to create planning list: #{e.message}"
      {
        success: false,
        error: e.message
      }
    end
  end

  def create_list(title, description = nil)
    return { success: false, error: "Title is required to create a list" } if title.blank?

    if description.blank?
      description = generate_smart_description(title, nil, nil)
    end

    begin
      service = ListCreationService.new(@user)
      list = service.create_list(title: title, description: description)

      {
        success: true,
        message: "Created list '#{list.title}'",
        list: serialize_list(list)
      }
    rescue => e
      {
        success: false,
        error: e.message
      }
    end
  end

  def add_item(list_id, title, description = nil)
    return { success: false, error: "Title is required to add an item" } if title.blank?

    # ENHANCED: Resolve list using context-aware method
    list = resolve_list_reference(list_id)
    return { success: false, error: "List not found or you don't have permission to modify it" } unless list

    Rails.logger.info "Adding item '#{title}' to list '#{list.title}' (#{list.id})"

    items_service = ListItemService.new(list, @user)
    result = items_service.create_item(
      title: title,
      description: description || "Added via AI assistant"
    )

    if result.success?
      item = result.data
      {
        success: true,
        message: "Added item '#{item.title}' to list '#{list.title}'",
        item: serialize_item(item)
      }
    else
      {
        success: false,
        error: result.errors.join(", ")
      }
    end
  end

  def complete_item(list_id, item_id)
    return { success: false, error: "List ID and item ID are required" } if list_id.blank? || item_id.blank?

    # ENHANCED: Resolve list using context-aware method
    list = resolve_list_reference(list_id)
    return { success: false, error: "List not found or you don't have permission to modify it" } unless list

    item = list.list_items.find_by(id: item_id)
    return { success: false, error: "Item not found in this list" } unless item

    items_service = ListItemService.new(list, @user)
    result = items_service.complete_item(item.id)

    if result.success?
      {
        success: true,
        message: "Marked item '#{item.title}' as completed",
        item: serialize_item(item.reload)
      }
    else
      {
        success: false,
        error: result.errors.join(", ")
      }
    end
  end

  def get_lists
    # Replace .recent with .order(updated_at: :desc)
    lists = @user.accessible_lists.order(updated_at: :desc).limit(20)

    {
      success: true,
      lists: lists.map { |list| serialize_list(list) }
    }
  end

  def get_list_items(list_id)
    return { success: false, error: "List ID is required" } if list_id.blank?

    # ENHANCED: Resolve list using context-aware method
    list = resolve_list_reference(list_id)
    return { success: false, error: "List not found or you don't have permission to view it" } unless list

    items = list.list_items.order(:position, :created_at)

    {
      success: true,
      list: serialize_list(list),
      items: items.map { |item| serialize_item(item) }
    }
  end

  # ENHANCED: Context-aware list resolution
  def resolve_list_reference(list_reference)
    return nil if list_reference.blank?

    Rails.logger.info "Resolving list reference: '#{list_reference}'"

    # 1. Try direct UUID lookup first (fastest path)
    if list_reference.match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
      list = find_accessible_list(list_reference)
      if list
        Rails.logger.info "Found list by UUID: #{list.title}"
        return list
      end
    end

    # 2. Handle contextual references (this list, current list, etc.)
    if list_reference.match?(/\b(this|current|the)\s+(list|todo)\b/i)
      Rails.logger.info "Resolving contextual reference: #{list_reference}"
      context_list = @context_manager.resolve_current_list
      if context_list && context_list[:id]
        list = find_accessible_list(context_list[:id])
        if list
          Rails.logger.info "Found list via context: #{list.title}"
          return list
        end
      end
    end

    # 3. Try finding by exact title match
    list = @user.accessible_lists.find_by(title: list_reference)
    if list
      Rails.logger.info "Found list by exact title: #{list.title}"
      return list
    end

    # 4. Try case-insensitive title search
    list = @user.accessible_lists.where("title ILIKE ?", list_reference).first
    if list
      Rails.logger.info "Found list by case-insensitive title: #{list.title}"
      return list
    end

    # 5. Fall back to conversation context if no explicit list_id provided
    if list_reference.blank? || list_reference.match?(/\b(list|todo)\b/i)
      Rails.logger.info "Falling back to conversation context"
      context_list = @context_manager.resolve_current_list
      if context_list && context_list[:id]
        list = find_accessible_list(context_list[:id])
        if list
          Rails.logger.info "Found list via fallback context: #{list.title}"
          return list
        end
      end
    end

    Rails.logger.warn "Could not resolve list reference: '#{list_reference}'"
    nil
  end

  # Helper methods
  def find_accessible_list(list_id)
    @user.accessible_lists.find_by(id: list_id)
  end

  def serialize_list(list)
    {
      id: list.id,
      title: list.title,
      description: list.description,
      status: list.status,
      items_count: list.list_items.count,
      completed_count: list.list_items.where(completed: true).count,
      created_at: list.created_at,
      updated_at: list.updated_at
    }
  end

  def serialize_list_with_items(list)
    base_list = serialize_list(list)

    if list.list_items.any?
      base_list[:items] = list.list_items.order(:position).map { |item| serialize_item(item) }
    end

    base_list
  end

  def serialize_item(item)
    {
      id: item.id,
      title: item.title,
      description: item.description,
      type: item.item_type,
      priority: item.priority,
      position: item.position,
      completed: item.completed,
      due_date: item.due_date,
      created_at: item.created_at,
      updated_at: item.updated_at
    }
  end

  def generate_smart_description(title, context = nil)
    if context.present?
      "Organized planning for #{title.downcase} with focus on #{context}"
    else
      "An organized approach to #{title.downcase}"
    end
  end

  def extract_user_message_from_context
    # Get the most recent user message from the current chat
    @user.current_chat&.messages&.where(role: "user")&.last&.content
  end

  def enhance_planning_context(base_context, title, analysis)
    # Start with existing mapper
    mapped_context = PlanningContextMapper.map_context(base_context || "", title)

    # Enhance based on complexity analysis
    if analysis[:location_analysis][:travel_related]
      mapped_context = "travel #{mapped_context}"
    end

    if analysis[:external_service_analysis][:needs_external_services]
      service_types = analysis[:external_service_analysis][:service_categories]
      if service_types[:booking]
        mapped_context = "booking and #{mapped_context}"
      end
    end

    if analysis[:list_type_classification][:primary_type] != "mixed"
      type = analysis[:list_type_classification][:primary_type]
      mapped_context = "#{type} #{mapped_context}"
    end

    mapped_context
  end

  def generate_smart_description(title, planning_context, analysis = nil)
    if analysis
      base_desc = "#{title} planning"

      complexity_notes = []
      if analysis[:location_analysis][:multiple_locations]
        complexity_notes << "across multiple locations"
      end

      if analysis[:external_service_analysis][:needs_external_services]
        complexity_notes << "with external service coordination"
      end

      if analysis[:hierarchical_needs][:needs_hierarchy]
        complexity_notes << "organized in phases"
      end

      complexity_notes.any? ? "#{base_desc} #{complexity_notes.join(' and ')}" : base_desc
    else
      "#{title} planning and organization"
    end
  end

  def build_success_message_with_complexity(list, analysis)
    base_message = "Created planning list '#{list.title}' with #{list.list_items.count} initial items"

    insights = []
    case analysis[:complexity_level]
    when "complex", "very_complex"
      insights << "organized into structured phases due to complexity"
    when "moderate"
      insights << "with organized planning approach"
    end

    if analysis[:location_analysis][:multiple_locations]
      insights << "including multi-location coordination"
    end

    insights.any? ? "#{base_message} #{insights.join(' and ')}" : base_message
  end

  def extract_user_friendly_insights(analysis)
    {
      complexity: {
        level: analysis[:complexity_level],
        user_friendly: complexity_level_description(analysis[:complexity_level])
      },
      special_features: extract_special_features(analysis),
      recommendations: extract_recommendations(analysis)
    }
  end

  def complexity_level_description(level)
    {
      "simple" => "Quick and straightforward",
      "moderate" => "Well-structured planning needed",
      "complex" => "Detailed coordination required",
      "very_complex" => "Comprehensive project management"
    }[level] || "Standard planning"
  end

  def extract_special_features(analysis)
    features = []
    features << "Multi-location coordination" if analysis[:location_analysis][:multiple_locations]
    features << "External service integration" if analysis[:external_service_analysis][:needs_external_services]
    features << "Hierarchical organization" if analysis[:hierarchical_needs][:needs_hierarchy]
    features << "Cultural adaptation" if analysis[:language_and_cultural_context][:detected_language] != "en"
    features
  end

  def extract_recommendations(analysis)
    recommendations = []

    if analysis[:complexity_score] >= 8
      recommendations << "Consider breaking into smaller phases"
    end

    if analysis[:external_service_analysis][:needs_external_services]
      recommendations << "Plan for external service dependencies"
    end

    if analysis[:location_analysis][:multiple_locations]
      recommendations << "Coordinate timing across locations"
    end

    recommendations
  end
end
