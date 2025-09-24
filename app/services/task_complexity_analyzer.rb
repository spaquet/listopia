# app/services/task_complexity_analyzer.rb
class TaskComplexityAnalyzer < ApplicationService
  include ActiveModel::Model
  include ActiveModel::Attributes

  class AnalysisError < StandardError; end

  # Minimal fallback keywords - only for when LLM analysis fails
  FALLBACK_INDICATORS = {
    location: %w[location travel city],
    multi_step: %w[plan steps phases],
    external_services: %w[book reservation meeting],
    professional: %w[project business meeting],
    personal: %w[family personal vacation],
    hierarchical: %w[breakdown phases organize]
  }.freeze

  attr_accessor :user, :context, :chat

  def initialize(user:, context: {}, chat: nil)
    @user = user
    @context = context || {}
    @chat = chat # Now properly utilized for conversation context
    @logger = Rails.logger

    # Initialize conversation context manager if chat is available
    if @chat
      @conversation_context_manager = ConversationContextManager.new(
        user: @user,
        chat: @chat,
        current_context: @context
      )
    end
  end

  # Main analysis method using LLM-first approach with chat context
  def analyze_complexity(user_message, additional_context: {})
    @logger.info "TaskComplexityAnalyzer: Starting LLM-based analysis for user #{@user.id}"

    begin
      # Extract conversation context from chat if available
      conversation_context = extract_conversation_context

      # Merge all contexts for comprehensive analysis
      enhanced_context = additional_context.merge(conversation_context)

      # Primary: Use LLM for intelligent analysis with chat context
      llm_analysis = perform_llm_analysis(user_message, enhanced_context)

      if llm_analysis[:success]
        @logger.debug "LLM analysis successful with chat context"
        return enhance_llm_analysis(llm_analysis[:data], user_message, conversation_context)
      else
        @logger.warn "LLM analysis failed: #{llm_analysis[:error]}"
      end

    rescue => e
      @logger.error "LLM analysis error: #{e.message}"
    end

    # Fallback: Use keyword-based heuristic analysis with chat context
    @logger.info "Using fallback heuristic analysis with chat context"
    fallback_analysis(user_message, additional_context.merge(extract_conversation_context))
  end

  # Quick complexity check using hybrid approach with chat awareness
  def quick_complexity_check(user_message)
    # Add conversation context for better quick analysis
    conversation_context = extract_conversation_context

    # Try LLM quick analysis first with context
    quick_llm_result = perform_quick_llm_analysis(user_message, conversation_context)

    if quick_llm_result[:success]
      return quick_llm_result[:data]
    end

    # Fallback to heuristic with context
    quick_heuristic_analysis(user_message, conversation_context)
  end

  private

  # Extract relevant context from the ongoing conversation
  def extract_conversation_context
    return {} unless @chat && @conversation_context_manager

    context = {
      chat_context: {
        chat_id: @chat.id,
        message_count: @chat.messages.count,
        conversation_age_minutes: conversation_age_in_minutes,
        has_recent_activity: @user.has_recent_activity?(hours: 1)
      }
    }

    # Add conversation patterns
    conversation_patterns = analyze_conversation_patterns
    context[:conversation_patterns] = conversation_patterns if conversation_patterns.present?

    # Add recent conversation topics
    recent_topics = extract_recent_conversation_topics
    context[:recent_topics] = recent_topics if recent_topics.present?

    # Add user's complexity preferences based on chat history
    complexity_preferences = analyze_user_complexity_preferences
    context[:user_complexity_preferences] = complexity_preferences if complexity_preferences.present?

    # Add current context summary from conversation manager
    if @conversation_context_manager
      context_summary = @conversation_context_manager.build_context_summary
      context[:current_context] = context_summary
    end

    @logger.debug "Extracted conversation context: #{context.keys.join(', ')}"
    context
  end

  # Analyze patterns in the user's conversation history
  def analyze_conversation_patterns
    return {} unless @chat && @chat.messages.count > 5

    recent_messages = @chat.messages.order(:created_at).limit(20)
    user_messages = recent_messages.where(role: "user")

    patterns = {
      average_message_length: calculate_average_message_length(user_messages),
      complexity_trend: analyze_complexity_trend(user_messages),
      planning_orientation: analyze_planning_orientation(user_messages),
      collaboration_indicators: analyze_collaboration_indicators(user_messages),
      time_horizon_preference: analyze_time_horizon_preference(user_messages)
    }

    patterns.compact
  end

  # Extract recent conversation topics to understand context continuity
  def extract_recent_conversation_topics
    return [] unless @chat

    recent_messages = @chat.messages
                           .where(role: [ "user", "assistant" ])
                           .order(:created_at)
                           .limit(10)

    topics = []

    recent_messages.each do |message|
      content = message.content&.downcase
      next unless content

      # Extract potential topics using simple keyword analysis
      if content.match?(/\b(list|task|plan|project|organize)\b/)
        if content.match?(/\b(travel|vacation|trip)\b/)
          topics << "travel_planning"
        elsif content.match?(/\b(work|business|meeting|project)\b/)
          topics << "work_planning"
        elsif content.match?(/\b(shopping|buy|purchase)\b/)
          topics << "shopping"
        elsif content.match?(/\b(event|party|wedding|celebration)\b/)
          topics << "event_planning"
        else
          topics << "general_planning"
        end
      end
    end

    topics.uniq.last(3) # Return last 3 unique topics
  end

  # Analyze user's historical complexity preferences based on their list creation patterns
  def analyze_user_complexity_preferences
    recent_lists = @user.lists.includes(:list_items)
                              .order(:created_at)
                              .limit(10)

    return {} if recent_lists.empty?

    preferences = {
      prefers_detailed_lists: calculate_detail_preference(recent_lists),
      typical_list_size: calculate_typical_list_size(recent_lists),
      uses_hierarchical_structure: analyze_hierarchy_usage(recent_lists),
      completion_rate: calculate_completion_rate(recent_lists),
      planning_depth_preference: analyze_planning_depth(recent_lists)
    }

    preferences.compact
  end

  # Calculate how long the conversation has been active
  def conversation_age_in_minutes
    return 0 unless @chat&.created_at
    ((Time.current - @chat.created_at) / 60).round(1)
  end

  # Enhanced LLM analysis with conversation context
  def perform_llm_analysis(user_message, enhanced_context)
    # Use the original chat for analysis but with specific context instructions
    analysis_chat = prepare_chat_for_analysis(enhanced_context)

    analysis_prompt = build_llm_analysis_prompt_with_context(user_message, enhanced_context)

    begin
      response = analysis_chat.ask(analysis_prompt)
      parsed_result = parse_llm_analysis_response(response.content)

      validate_llm_analysis!(parsed_result)

      { success: true, data: parsed_result }
    rescue => e
      @logger.error "LLM analysis failed: #{e.message}"
      { success: false, error: e.message }
    end
  end

  # Prepare the original chat for analysis with context-aware instructions
  def prepare_chat_for_analysis(context)
    if @chat
      # Add context-aware instructions to the existing chat
      context_instructions = build_analysis_context_instructions(context)
      @chat.with_instructions(context_instructions, replace: false)
      @chat
    else
      # Fallback to creating a new analysis chat
      create_analysis_chat
    end
  end

  # Build context-aware instructions for the analysis
  def build_analysis_context_instructions(context)
    instructions = [ "You are analyzing a task request with the following conversation context:" ]

    if context[:chat_context].present?
      chat_ctx = context[:chat_context]
      instructions << "This is message ##{chat_ctx[:message_count]} in a #{chat_ctx[:conversation_age_minutes]}-minute conversation."
    end

    if context[:recent_topics].present?
      instructions << "Recent conversation topics: #{context[:recent_topics].join(', ')}"
    end

    if context[:user_complexity_preferences].present?
      prefs = context[:user_complexity_preferences]
      if prefs[:prefers_detailed_lists]
        instructions << "User typically prefers detailed, well-structured lists."
      end
      if prefs[:typical_list_size] && prefs[:typical_list_size] > 10
        instructions << "User typically works with larger lists (#{prefs[:typical_list_size]} items average)."
      end
    end

    if context[:conversation_patterns].present?
      patterns = context[:conversation_patterns]
      if patterns[:planning_orientation] == "high"
        instructions << "User demonstrates strong planning orientation in conversations."
      end
      if patterns[:collaboration_indicators]
        instructions << "User frequently engages in collaborative planning."
      end
    end

    instructions << "Consider this context when assessing task complexity and requirements."
    instructions.join("\n\n")
  end

  def build_llm_analysis_prompt_with_context(user_message, enhanced_context)
    context_info = build_context_string(enhanced_context)
    conversation_context = build_conversation_context_string(enhanced_context)

    <<~PROMPT
      You are an expert task complexity analyzer for a list management application.
      Analyze the following user request for complexity factors and classification.

      USER MESSAGE: "#{user_message}"

      CONTEXT INFORMATION:
      #{context_info}

      CONVERSATION CONTEXT:
      #{conversation_context}

      Provide a comprehensive JSON analysis:
      {
        "complexity_score": 1-10,
        "complexity_level": "simple|moderate|complex|very_complex",
        "complexity_factors": ["factor1", "factor2"],
        "list_type_classification": {
          "primary_type": "professional|personal|mixed",
          "confidence_percentage": 1-100,
          "type_indicators": ["indicator1", "indicator2"]
        },
        "multi_step_analysis": {
          "has_multi_step_elements": true/false,
          "estimated_steps": 1-20,
          "coordination_required": true/false,
          "time_dependencies": true/false
        },
        "external_service_analysis": {
          "needs_external_services": true/false,
          "service_types": ["booking", "location", "communication"],
          "integration_complexity": "low|medium|high"
        },
        "hierarchical_analysis": {
          "needs_hierarchical_structure": true/false,
          "estimated_levels": 1-5,
          "parent_child_relationships": true/false
        },
        "resource_requirements": {
          "time_commitment": "low|medium|high",
          "coordination_needs": "individual|team|multi_team",
          "skill_requirements": ["skill1", "skill2"]
        },
        "conversation_context_influence": {
          "context_relevance": "low|medium|high",
          "builds_on_previous": true/false,
          "complexity_adjustment": -2 to +2
        }
      }

      Focus on practical execution complexity rather than keyword matching.
      Consider how conversation context influences the actual complexity.
      Only respond with valid JSON.
    PROMPT
  end

  # Build conversation context string for the prompt
  def build_conversation_context_string(enhanced_context)
    context_parts = []

    if enhanced_context[:chat_context].present?
      chat_ctx = enhanced_context[:chat_context]
      context_parts << "Conversation: Message ##{chat_ctx[:message_count]}, #{chat_ctx[:conversation_age_minutes]} minutes old"
    end

    if enhanced_context[:recent_topics].present?
      context_parts << "Recent topics: #{enhanced_context[:recent_topics].join(', ')}"
    end

    if enhanced_context[:user_complexity_preferences].present?
      prefs = enhanced_context[:user_complexity_preferences]
      context_parts << "User preferences: #{prefs.keys.join(', ')}"
    end

    if enhanced_context[:conversation_patterns].present?
      patterns = enhanced_context[:conversation_patterns]
      context_parts << "Conversation patterns: #{patterns.keys.join(', ')}"
    end

    context_parts.any? ? context_parts.join("\n") : "No conversation context available"
  end

  # Enhanced LLM analysis enhancement with conversation context
  def enhance_llm_analysis(llm_data, user_message, conversation_context = {})
    enhanced_data = llm_data.dup

    # Apply conversation context adjustments
    if conversation_context[:conversation_patterns].present?
      patterns = conversation_context[:conversation_patterns]

      # Adjust complexity based on user's historical patterns
      if patterns[:complexity_trend] == "increasing"
        enhanced_data[:complexity_score] = [ enhanced_data[:complexity_score] + 1, 10 ].min
        enhanced_data[:complexity_factors] << "user_complexity_trend_increasing"
      end

      if patterns[:planning_orientation] == "high"
        enhanced_data[:hierarchical_analysis][:needs_hierarchical_structure] = true
      end
    end

    # Apply user complexity preferences
    if conversation_context[:user_complexity_preferences].present?
      prefs = conversation_context[:user_complexity_preferences]

      if prefs[:prefers_detailed_lists] && enhanced_data[:complexity_score] < 5
        enhanced_data[:complexity_score] += 1
        enhanced_data[:complexity_factors] << "user_prefers_detailed_structure"
      end
    end

    # Add conversation context metadata
    enhanced_data[:analysis_metadata] = {
      used_conversation_context: conversation_context.present?,
      context_influence_applied: conversation_context.any?,
      chat_id: @chat&.id,
      analysis_timestamp: Time.current.iso8601
    }

    enhanced_data
  end

  # Enhanced quick analysis with conversation context
  def perform_quick_llm_analysis(user_message, conversation_context = {})
    analysis_chat = prepare_chat_for_analysis(conversation_context)

    context_summary = conversation_context[:current_context] || {}

    quick_prompt = <<~PROMPT
      Quick task complexity analysis with conversation context:

      REQUEST: "#{user_message}"
      CONVERSATION CONTEXT: #{conversation_context.keys.join(', ')}
      CURRENT CONTEXT: #{context_summary.keys.join(', ')}

      {
        "complexity_score": 1-10,
        "requires_planning": boolean,
        "list_type": "professional|personal|mixed",
        "multi_step": boolean,
        "context_influence": "none|low|medium|high",
        "quick_reasoning": "brief explanation considering conversation context"
      }

      JSON only, no other text.
    PROMPT

    begin
      response = analysis_chat.ask(quick_prompt)
      parsed_result = JSON.parse(clean_json_response(response.content), symbolize_names: true)

      { success: true, data: parsed_result }
    rescue => e
      @logger.error "Quick LLM analysis failed: #{e.message}"
      { success: false, error: e.message }
    end
  end

  # Helper methods for conversation analysis
  def calculate_average_message_length(messages)
    return 0 if messages.empty?
    total_length = messages.sum { |msg| msg.content&.length || 0 }
    (total_length.to_f / messages.count).round(1)
  end

  def analyze_complexity_trend(messages)
    return "stable" if messages.count < 5

    # Simple heuristic: longer messages often indicate more complex requests
    recent_avg = messages.last(3).sum { |msg| msg.content&.length || 0 } / 3.0
    earlier_avg = messages.first(3).sum { |msg| msg.content&.length || 0 } / 3.0

    if recent_avg > earlier_avg * 1.3
      "increasing"
    elsif recent_avg < earlier_avg * 0.7
      "decreasing"
    else
      "stable"
    end
  end

  def analyze_planning_orientation(messages)
    planning_keywords = %w[plan organize schedule structure phases steps workflow]
    planning_count = messages.count do |msg|
      content = msg.content&.downcase || ""
      planning_keywords.any? { |keyword| content.include?(keyword) }
    end

    ratio = planning_count.to_f / messages.count
    ratio > 0.3 ? "high" : "low"
  end

  def analyze_collaboration_indicators(messages)
    collab_keywords = %w[we team share collaborate together group]
    messages.any? do |msg|
      content = msg.content&.downcase || ""
      collab_keywords.any? { |keyword| content.include?(keyword) }
    end
  end

  def analyze_time_horizon_preference(messages)
    short_term = %w[today tomorrow this week urgent immediate]
    long_term = %w[month quarter year future long-term strategic]

    short_count = messages.count { |msg| short_term.any? { |word| msg.content&.downcase&.include?(word) } }
    long_count = messages.count { |msg| long_term.any? { |word| msg.content&.downcase&.include?(word) } }

    if short_count > long_count
      "short_term"
    elsif long_count > short_count
      "long_term"
    else
      "mixed"
    end
  end

  def calculate_detail_preference(lists)
    avg_items_per_list = lists.sum { |list| list.list_items.count }.to_f / lists.count
    avg_items_per_list > 7 # Consider detailed if average > 7 items per list
  end

  def calculate_typical_list_size(lists)
    return 0 if lists.empty?
    lists.sum { |list| list.list_items.count } / lists.count
  end

  def analyze_hierarchy_usage(lists)
    # Simple heuristic: look for lists with related titles or structured naming
    structured_count = lists.count do |list|
      title = list.title.downcase
      title.match?(/phase|step|part|\d+\.|\w+:/) || list.list_items.any? { |item| item.title.match?(/\d+\.|\w+:/) }
    end

    (structured_count.to_f / lists.count) > 0.3
  end

  def calculate_completion_rate(lists)
    return 0 if lists.empty?

    total_items = lists.sum { |list| list.list_items.count }
    return 0 if total_items == 0

    completed_items = lists.sum { |list| list.list_items.count(&:completed) }
    (completed_items.to_f / total_items * 100).round(1)
  end

  def analyze_planning_depth(lists)
    depth_indicators = lists.count do |list|
      # Look for indicators of deep planning: long descriptions, metadata, structured items
      has_detailed_description = list.description.present? && list.description.length > 100
      has_structured_items = list.list_items.any? { |item| item.description.present? && item.description.length > 50 }
      has_metadata_planning = list.metadata.present? && list.metadata.keys.any? { |key| key.to_s.match?(/planning|workflow|phase/) }

      has_detailed_description || has_structured_items || has_metadata_planning
    end

    ratio = depth_indicators.to_f / lists.count
    if ratio > 0.4
      "deep"
    elsif ratio > 0.2
      "moderate"
    else
      "shallow"
    end
  end

  # Rest of the existing methods remain the same...
  def create_analysis_chat
    Chat.new(
      user: @user,
      title: "Task Complexity Analysis - #{Time.current.to_i}",
      status: "analysis"
    )
  end

  def build_context_string(additional_context)
    full_context = @context.merge(additional_context)

    context_parts = []
    context_parts << "Page: #{full_context[:page]}" if full_context[:page]
    context_parts << "Time: #{full_context[:time_context]}" if full_context[:time_context]
    context_parts << "User Location: #{full_context[:user_location]}" if full_context[:user_location]
    context_parts << "Previous Lists: #{full_context[:recent_lists]}" if full_context[:recent_lists]

    context_parts.any? ? context_parts.join("\n") : "No additional context available"
  end

  def clean_json_response(response)
    # Remove markdown code blocks
    cleaned = response.gsub(/```json\n?/, "").gsub(/```\n?/, "")

    # Find JSON boundaries
    json_start = cleaned.index("{")
    json_end = cleaned.rindex("}")

    if json_start && json_end && json_end > json_start
      cleaned[json_start..json_end]
    else
      cleaned.strip
    end
  end

  # LLM-based complexity analysis
  def perform_llm_analysis(user_message, additional_context)
    analysis_chat = create_analysis_chat

    analysis_prompt = build_llm_analysis_prompt(user_message, additional_context)

    begin
      response = analysis_chat.ask(analysis_prompt)
      parsed_result = parse_llm_analysis_response(response.content)

      validate_llm_analysis!(parsed_result)

      { success: true, data: parsed_result }
    rescue => e
      @logger.error "LLM analysis failed: #{e.message}"
      { success: false, error: e.message }
    end
  end

  def parse_llm_analysis_response(response_content)
    # Clean JSON response
    json_content = clean_json_response(response_content)

    begin
      parsed = JSON.parse(json_content, symbolize_names: true)

      # Add metadata
      parsed[:analysis_metadata] = {
        analyzed_at: Time.current,
        user_id: @user.id,
        analysis_method: "llm_primary",
        analysis_version: "2.0"
      }

      parsed
    rescue JSON::ParserError => e
      raise AnalysisError, "Failed to parse LLM analysis response: #{e.message}"
    end
  end

  # Fallback heuristic analysis (minimal keywords)
  def fallback_analysis(user_message, additional_context)
    @logger.warn "Using fallback keyword analysis"

    message_lower = user_message.downcase
    full_context = @context.merge(additional_context)

    # Basic complexity scoring
    complexity_score = calculate_fallback_complexity_score(message_lower)

    {
      complexity_score: complexity_score,
      complexity_level: determine_complexity_level_from_score(complexity_score),
      location_analysis: analyze_location_fallback(message_lower),
      multi_step_analysis: analyze_multi_step_fallback(message_lower),
      external_service_analysis: analyze_external_services_fallback(message_lower),
      list_type_classification: classify_list_type_fallback(message_lower, full_context),
      hierarchical_needs: assess_hierarchical_needs_fallback(message_lower),
      language_and_cultural_context: {
        detected_language: "unknown",
        cultural_context: "unknown",
        regional_considerations: "none detected"
      },
      planning_context_compatibility: assess_planning_context_compatibility_fallback(user_message),
      execution_recommendations: { approach: "standard", notes: "limited analysis available" },
      risk_assessment: { level: "medium", factors: [ "limited analysis" ] },
      analysis_metadata: {
        analyzed_at: Time.current,
        user_id: @user.id,
        analysis_method: "fallback_heuristic",
        analysis_version: "2.0_fallback"
      }
    }
  end

  def quick_heuristic_analysis(user_message)
    message_lower = user_message.downcase

    # Very basic keyword matching for fallback
    complexity_score = [
      count_keyword_matches(message_lower, FALLBACK_INDICATORS[:location]),
      count_keyword_matches(message_lower, FALLBACK_INDICATORS[:multi_step]) * 2,
      count_keyword_matches(message_lower, FALLBACK_INDICATORS[:external_services])
    ].sum + 1

    {
      complexity_score: [ complexity_score, 10 ].min,
      requires_planning: complexity_score >= 4,
      list_type: classify_type_simple(message_lower),
      multi_location: has_keywords?(message_lower, FALLBACK_INDICATORS[:location]),
      external_services: has_keywords?(message_lower, FALLBACK_INDICATORS[:external_services]),
      quick_reasoning: "Heuristic analysis based on limited keywords"
    }
  end

  # Helper methods for fallback analysis
  def calculate_fallback_complexity_score(message)
    score = 1

    FALLBACK_INDICATORS.each do |category, keywords|
      matches = count_keyword_matches(message, keywords)
      score += case category
      when :location then [ matches, 2 ].min
      when :multi_step then [ matches * 2, 3 ].min
      when :external_services then [ matches, 2 ].min
      when :hierarchical then [ matches, 2 ].min
      else matches
      end
    end

    [ score, 10 ].min
  end

  def analyze_location_fallback(message)
    location_keywords = FALLBACK_INDICATORS[:location]
    matches = location_keywords.select { |kw| message.include?(kw) }

    {
      has_location_elements: matches.any?,
      multiple_locations: message.match?(/multiple|several|various/) && matches.any?,
      travel_related: message.match?(/travel|trip|flight/),
      location_types: matches,
      complexity_reasoning: "Fallback analysis - limited keyword detection"
    }
  end

  def analyze_multi_step_fallback(message)
    step_keywords = FALLBACK_INDICATORS[:multi_step]
    matches = step_keywords.select { |kw| message.include?(kw) }

    # Simple step count estimation
    explicit_steps = message.scan(/step \d+|phase \d+|\d+\.|\d+\)/).length
    estimated_steps = explicit_steps > 0 ? explicit_steps : (matches.any? ? 3 : 1)

    {
      has_multi_step_elements: matches.any? || explicit_steps > 0,
      estimated_step_count: estimated_steps,
      sequential_dependencies: message.match?(/then|after|before|sequence/),
      parallel_tasks_possible: message.match?(/parallel|simultaneously|same time/),
      complexity_reasoning: "Basic pattern matching for steps and sequences"
    }
  end

  def classify_list_type_fallback(message, context)
    prof_matches = count_keyword_matches(message, FALLBACK_INDICATORS[:professional])
    pers_matches = count_keyword_matches(message, FALLBACK_INDICATORS[:personal])

    # Add context influence
    context_bias = calculate_context_bias(context)
    prof_score = prof_matches + context_bias[:professional]
    pers_score = pers_matches + context_bias[:personal]

    primary_type = if prof_score > pers_score
      "professional"
    elsif pers_score > prof_score
      "personal"
    else
      "mixed"
    end

    total_indicators = prof_score + pers_score
    confidence = total_indicators > 0 ?
      [ (prof_score - pers_score).abs.to_f / total_indicators * 100, 100 ].min : 25

    {
      primary_type: primary_type,
      confidence_percentage: confidence.round(1),
      type_indicators: prof_matches + pers_matches,
      classification_reasoning: "Keyword-based classification with context bias"
    }
  end

  def count_keyword_matches(text, keywords)
    keywords.count { |keyword| text.include?(keyword) }
  end

  def has_keywords?(text, keywords)
    keywords.any? { |keyword| text.include?(keyword) }
  end

  def classify_type_simple(message)
    prof_count = count_keyword_matches(message, FALLBACK_INDICATORS[:professional])
    pers_count = count_keyword_matches(message, FALLBACK_INDICATORS[:personal])

    if prof_count > pers_count
      "professional"
    elsif pers_count > prof_count
      "personal"
    else
      "mixed"
    end
  end

  def calculate_context_bias(context)
    professional_bias = 0
    personal_bias = 0

    if context[:page]&.match?(/work|business|project|admin/)
      professional_bias += 1
    elsif context[:page]&.match?(/personal|home|family/)
      personal_bias += 1
    end

    if context[:time_context] == "business_hours"
      professional_bias += 1
    elsif context[:time_context] == "evening_weekend"
      personal_bias += 1
    end

    { professional: professional_bias, personal: personal_bias }
  end

  def determine_complexity_level_from_score(score)
    case score
    when 1..3 then "simple"
    when 4..6 then "moderate"
    when 7..8 then "complex"
    when 9..10 then "very_complex"
    else "simple"
    end
  end

  def validate_llm_analysis!(analysis)
    required_fields = [
      :complexity_score, :complexity_level, :location_analysis,
      :multi_step_analysis, :external_service_analysis, :list_type_classification
    ]

    required_fields.each do |field|
      unless analysis.key?(field)
        raise AnalysisError, "Missing required field in LLM analysis: #{field}"
      end
    end
  end

  def assess_planning_context_compatibility_llm(suggested_context)
    available_contexts = PlanningContextMapper.available_contexts
    is_standard = available_contexts.include?(suggested_context)

    {
      mapped_context: suggested_context,
      is_standard_context: is_standard,
      suggests_new_context_needed: !is_standard,
      available_contexts: available_contexts,
      context_confidence: is_standard ? 90 : 60,
      integration_recommendation: {
        recommendation: is_standard ? "use_existing_context" : "consider_context_extension",
        context: suggested_context,
        confidence: is_standard ? "high" : "medium"
      }
    }
  end

  def generate_execution_recommendations(analysis)
    recommendations = []

    if analysis[:complexity_score] >= 8
      recommendations << "Break into smaller, manageable phases"
    end

    if analysis[:location_analysis][:multiple_locations]
      recommendations << "Consider separate lists or phases for each location"
    end

    if analysis[:external_service_analysis][:needs_external_services]
      recommendations << "Plan for external service dependencies and potential delays"
    end

    {
      approach: determine_execution_approach(analysis[:complexity_score]),
      specific_recommendations: recommendations,
      estimated_duration: estimate_execution_duration(analysis)
    }
  end

  def assess_complexity_risks(analysis)
    risks = []
    risk_level = "low"

    if analysis[:complexity_score] >= 8
      risks << "High complexity may lead to overwhelm"
      risk_level = "high"
    end

    if analysis[:external_service_analysis][:needs_external_services]
      risks << "External service dependencies may cause delays"
      risk_level = "medium" if risk_level == "low"
    end

    if analysis[:location_analysis][:multiple_locations]
      risks << "Coordination across locations increases complexity"
      risk_level = "medium" if risk_level == "low"
    end

    {
      level: risk_level,
      factors: risks,
      mitigation_suggestions: generate_mitigation_suggestions(risks)
    }
  end

  def determine_execution_approach(complexity_score)
    case complexity_score
    when 1..3 then "direct"
    when 4..6 then "structured"
    when 7..8 then "phased"
    when 9..10 then "comprehensive_planning"
    else "standard"
    end
  end

  def estimate_execution_duration(analysis)
    base_duration = case analysis[:complexity_score]
    when 1..3 then "30 minutes - 2 hours"
    when 4..6 then "2 hours - 1 day"
    when 7..8 then "1 day - 1 week"
    when 9..10 then "1 week - 1 month"
    else "unknown"
    end

    # Adjust for specific factors
    if analysis[:location_analysis][:multiple_locations]
      base_duration += " (extended for multi-location coordination)"
    end

    base_duration
  end

  def generate_mitigation_suggestions(risks)
    suggestions = []

    risks.each do |risk|
      case risk
      when /complexity.*overwhelm/
        suggestions << "Use hierarchical structure to break down tasks"
      when /external service/
        suggestions << "Build in buffer time and have backup options"
      when /coordination.*locations/
        suggestions << "Assign location coordinators and use shared calendars"
      end
    end

    suggestions
  end

  # Maintain existing methods for backward compatibility
  def assess_planning_context_compatibility_fallback(user_message)
    mapped_context = PlanningContextMapper.map_context(user_message, "")
    available_contexts = PlanningContextMapper.available_contexts
    is_standard = available_contexts.include?(mapped_context)

    {
      mapped_context: mapped_context,
      is_standard_context: is_standard,
      suggests_new_context_needed: !is_standard,
      available_contexts: available_contexts,
      context_confidence: is_standard ? 70 : 30,
      integration_recommendation: {
        recommendation: is_standard ? "use_existing_context" : "consider_context_extension",
        context: mapped_context,
        confidence: is_standard ? "medium" : "low"
      }
    }
  end

  def analyze_external_services_fallback(message)
    service_keywords = FALLBACK_INDICATORS[:external_services]
    matches = service_keywords.select { |kw| message.include?(kw) }

    {
      needs_external_services: matches.any?,
      service_categories: {
        booking: message.match?(/book|reservation/),
        communication: message.match?(/meeting|call|email/),
        research: message.match?(/research|find|search/),
        commerce: message.match?(/buy|purchase|order/),
        integration: message.match?(/api|integration|sync/)
      },
      service_reasoning: "Basic pattern matching - limited analysis"
    }
  end

  def assess_hierarchical_needs_fallback(message)
    hierarchy_keywords = FALLBACK_INDICATORS[:hierarchical]
    matches = hierarchy_keywords.select { |kw| message.include?(kw) }

    {
      needs_hierarchy: matches.any? || message.match?(/phase|level|breakdown/),
      estimated_depth: matches.any? ? 2 : 1,
      hierarchy_type: determine_hierarchy_type_simple(message),
      hierarchy_reasoning: "Simple keyword-based detection"
    }
  end

  def determine_hierarchy_type_simple(message)
    return "phases" if message.match?(/phase/)
    return "timeline" if message.match?(/timeline|schedule/)
    return "categories" if message.match?(/category|organize/)
    return "nested_tasks" if message.match?(/breakdown|subtask/)
    "phases"
  end
end
