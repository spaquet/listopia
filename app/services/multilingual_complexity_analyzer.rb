# app/services/multilingual_complexity_analyzer.rb
class MultilingualComplexityAnalyzer < TaskComplexityAnalyzer
  include ActionView::Helpers::TranslationHelper

  # Language detection and cultural context mapping
  CULTURAL_CONTEXTS = {
    "en" => { business_formality: "medium", time_orientation: "monochronic" },
    "es" => { business_formality: "high", time_orientation: "polychronic" },
    "fr" => { business_formality: "high", time_orientation: "monochronic" },
    "de" => { business_formality: "high", time_orientation: "monochronic" },
    "ja" => { business_formality: "very_high", time_orientation: "monochronic" },
    "zh" => { business_formality: "high", time_orientation: "polychronic" }
  }.freeze

  def initialize(user:, context: {}, chat: nil, locale: nil)
    super(user: user, context: context, chat: chat)
    @locale = locale || user.locale || I18n.locale || :en
    @cultural_context = CULTURAL_CONTEXTS[@locale.to_s] || CULTURAL_CONTEXTS["en"]
  end

  # Override to include cultural context in analysis
  def analyze_complexity(user_message, additional_context: {})
    # Detect language if not provided
    detected_language = detect_language(user_message)

    # Add cultural context to analysis
    cultural_context = additional_context.merge({
      detected_language: detected_language,
      user_locale: @locale,
      cultural_factors: @cultural_context
    })

    super(user_message, additional_context: cultural_context)
  end

  private

  # Build culturally-aware LLM prompt
  def build_llm_analysis_prompt(user_message, additional_context)
    cultural_instructions = build_cultural_instructions(additional_context)
    localized_system_message = t("complexity_analysis.prompts.analysis_system_message", locale: @locale)

    <<~PROMPT
      #{localized_system_message}

      #{cultural_instructions}

      USER REQUEST: "#{user_message}"

      CONTEXT INFORMATION:
      #{build_context_string(additional_context)}

      CULTURAL CONTEXT:
      - Detected Language: #{additional_context[:detected_language]}
      - Cultural Business Style: #{@cultural_context[:business_formality]}
      - Time Orientation: #{@cultural_context[:time_orientation]}

      Please analyze this request with cultural sensitivity and respond with JSON:

      {
        "complexity_score": 1-10,
        "complexity_level": "simple|moderate|complex|very_complex",
        "location_analysis": {
          "has_location_elements": boolean,
          "multiple_locations": boolean,
          "travel_related": boolean,
          "location_types": ["detected location types"],
          "cultural_location_factors": "any culture-specific location considerations",
          "complexity_reasoning": "explain location complexity in context"
        },
        "multi_step_analysis": {
          "has_multi_step_elements": boolean,
          "estimated_step_count": number,
          "sequential_dependencies": boolean,
          "parallel_tasks_possible": boolean,
          "cultural_process_considerations": "culture-specific process factors",
          "complexity_reasoning": "explain process complexity"
        },
        "external_service_analysis": {
          "needs_external_services": boolean,
          "service_categories": {
            "booking": boolean,
            "communication": boolean,
            "research": boolean,
            "commerce": boolean,
            "integration": boolean,
            "cultural_services": boolean
          },
          "cultural_service_considerations": "culture-specific service requirements",
          "service_reasoning": "explain service needs with cultural context"
        },
        "list_type_classification": {
          "primary_type": "professional|personal|mixed",
          "confidence_percentage": 0-100,
          "cultural_classification_factors": ["culture-specific indicators"],
          "type_indicators": ["universal and cultural indicators"],
          "classification_reasoning": "explain classification with cultural awareness"
        },
        "hierarchical_needs": {
          "needs_hierarchy": boolean,
          "estimated_depth": 1-5,
          "hierarchy_type": "phases|categories|nested_tasks|timeline",
          "cultural_hierarchy_preferences": "culture-specific organizational preferences",
          "hierarchy_reasoning": "explain hierarchical needs with cultural context"
        },
        "language_and_cultural_context": {
          "detected_language": "language code",
          "confidence_language_detection": 0-100,
          "cultural_context": "business|personal|academic|informal",
          "regional_considerations": "specific cultural or regional factors",
          "communication_style": "direct|indirect|formal|informal",
          "time_orientation_impact": "how cultural time orientation affects task planning"
        },
        "planning_context_compatibility": {
          "suggested_context": "recommended planning context type",
          "fits_existing_patterns": boolean,
          "cultural_context_adaptations": "any cultural adaptations needed",
          "extension_needed": boolean,
          "context_reasoning": "explain context recommendation with cultural awareness"
        }
      }

      CULTURAL ANALYSIS GUIDELINES:
      - Consider how different cultures approach planning and organization
      - Recognize that business vs personal indicators vary by culture
      - Account for different communication styles (direct vs indirect)
      - Consider time orientation (monochronic vs polychronic cultures)
      - Be aware of hierarchy preferences in different cultures
      - Understand formality expectations vary by culture
      - Consider language-specific expressions and idioms
      - Don't rely on literal keyword matching - understand intent

      EXAMPLES OF CULTURAL CONSIDERATIONS:
      - In high-context cultures, implicit coordination may be assumed
      - Formal cultures may require more structured approaches
      - Polychronic cultures may plan multiple parallel activities
      - Some cultures prefer detailed hierarchy, others prefer flat structures

      Respond ONLY with valid JSON. No explanatory text outside the JSON structure.
    PROMPT
  end

  def build_cultural_instructions(context)
    instructions = []

    case @cultural_context[:business_formality]
    when "very_high"
      instructions << "This culture values formal, detailed planning with clear hierarchies."
    when "high"
      instructions << "This culture appreciates structured, well-organized planning."
    when "medium"
      instructions << "This culture balances formal and informal planning approaches."
    end

    case @cultural_context[:time_orientation]
    when "monochronic"
      instructions << "This culture typically prefers sequential, time-focused planning."
    when "polychronic"
      instructions << "This culture may be comfortable with parallel activities and flexible timing."
    end

    instructions.join(" ")
  end

  # Language detection using simple heuristics (could be enhanced with ML)
  def detect_language(text)
    # Simple language detection based on common words/patterns
    language_patterns = {
      "es" => %w[el la los las un una y que de con para por],
      "fr" => %w[le la les un une et que de avec pour par],
      "de" => %w[der die das ein eine und dass von mit für],
      "ja" => /[\u3040-\u309F\u30A0-\u30FF\u4E00-\u9FAF]/,
      "zh" => /[\u4E00-\u9FFF]/,
      "ar" => /[\u0600-\u06FF]/,
      "ru" => /[\u0400-\u04FF]/
    }

    text_lower = text.downcase

    # Check for non-Latin scripts first
    return "ja" if text.match?(language_patterns["ja"])
    return "zh" if text.match?(language_patterns["zh"])
    return "ar" if text.match?(language_patterns["ar"])
    return "ru" if text.match?(language_patterns["ru"])

    # Check Latin script languages
    language_patterns.each do |lang, patterns|
      next if patterns.is_a?(Regexp) # Skip regex patterns already checked

      if patterns.is_a?(Array)
        matches = patterns.count { |word| text_lower.include?(word) }
        return lang if matches >= 2
      end
    end

    "en" # Default to English
  end

  # Override for cultural context in quick analysis
  def perform_quick_llm_analysis(user_message)
    analysis_chat = create_analysis_chat
    quick_instruction = t("complexity_analysis.prompts.quick_analysis_instruction", locale: @locale)

    quick_prompt = <<~PROMPT
      #{quick_instruction}

      REQUEST: "#{user_message}"

      CULTURAL CONTEXT: #{@cultural_context}

      {
        "complexity_score": 1-10,
        "requires_planning": boolean,
        "list_type": "professional|personal|mixed",
        "multi_location": boolean,
        "external_services": boolean,
        "cultural_considerations": "brief cultural factors",
        "quick_reasoning": "brief explanation with cultural awareness"
      }

      JSON only, no other text.
    PROMPT

    begin
      response = analysis_chat.ask(quick_prompt)
      parsed = JSON.parse(clean_json_response(response.content), symbolize_names: true)
      { success: true, data: parsed }
    rescue => e
      { success: false, error: e.message }
    end
  end

  # Enhanced context building with cultural factors
  def build_context_string(additional_context)
    base_context = super(additional_context)

    cultural_context_parts = []
    if additional_context[:detected_language]
      cultural_context_parts << "Detected Language: #{additional_context[:detected_language]}"
    end

    if @cultural_context
      cultural_context_parts << "Business Formality: #{@cultural_context[:business_formality]}"
      cultural_context_parts << "Time Orientation: #{@cultural_context[:time_orientation]}"
    end

    if additional_context[:user_timezone]
      cultural_context_parts << "User Timezone: #{additional_context[:user_timezone]}"
    end

    cultural_section = cultural_context_parts.any? ?
      "\nCultural Context:\n#{cultural_context_parts.join('\n')}" : ""

    base_context + cultural_section
  end

  # Cultural fallback analysis
  def fallback_analysis(user_message, additional_context)
    base_analysis = super(user_message, additional_context)

    # Add cultural context to fallback
    base_analysis[:language_and_cultural_context] = {
      detected_language: detect_language(user_message),
      confidence_language_detection: 60, # Lower confidence for heuristic detection
      cultural_context: infer_cultural_context(user_message),
      regional_considerations: "Limited analysis - cultural factors may be missed",
      communication_style: infer_communication_style(user_message),
      time_orientation_impact: @cultural_context[:time_orientation]
    }

    # Adjust classification based on cultural context
    if @cultural_context[:business_formality] == "very_high"
      # In formal cultures, bias toward professional classification
      classification = base_analysis[:list_type_classification]
      if classification[:primary_type] == "mixed"
        classification[:primary_type] = "professional"
        classification[:classification_reasoning] += " (adjusted for high-formality culture)"
      end
    end

    base_analysis
  end

  def infer_cultural_context(message)
    # Simple heuristic inference
    if message.match?(/meeting|presentation|project|deadline/i)
      "business"
    elsif message.match?(/family|personal|vacation|home/i)
      "personal"
    elsif message.match?(/study|research|learn|course/i)
      "academic"
    else
      "general"
    end
  end

  def infer_communication_style(message)
    # Heuristic based on language patterns
    if message.length > 200 || message.match?(/please|kindly|would you|could you/i)
      "formal"
    elsif message.match?(/!|awesome|great|cool/) || message.length < 50
      "informal"
    else
      "neutral"
    end
  end
end

# app/services/adaptive_complexity_analyzer.rb
class AdaptiveComplexityAnalyzer < MultilingualComplexityAnalyzer
  # This service learns from user behavior and improves over time

  def initialize(user:, context: {}, chat: nil, locale: nil)
    super(user: user, context: context, chat: chat, locale: locale)
    @user_preferences = load_user_complexity_preferences
  end

  def analyze_complexity(user_message, additional_context: {})
    # Get base analysis
    base_analysis = super(user_message, additional_context: additional_context)

    # Adapt based on user preferences and history
    adapted_analysis = adapt_analysis_to_user_preferences(base_analysis, user_message)

    # Learn from this interaction
    learn_from_analysis(user_message, adapted_analysis)

    adapted_analysis
  end

  private

  def load_user_complexity_preferences
    # Load user's historical preferences
    user_lists = @user.lists.includes(:list_items)
                      .where.not("metadata->>'complexity_analysis' IS NULL")
                      .limit(20)

    preferences = {
      preferred_complexity_level: analyze_user_complexity_preference(user_lists),
      typical_list_size: calculate_typical_list_size(user_lists),
      hierarchy_preference: analyze_hierarchy_preference(user_lists),
      completion_patterns: analyze_completion_patterns(user_lists)
    }

    @logger.debug "Loaded user complexity preferences: #{preferences}"
    preferences
  end

  def adapt_analysis_to_user_preferences(analysis, user_message)
    adapted = analysis.deep_dup

    # Adjust complexity based on user's typical preference
    if @user_preferences[:preferred_complexity_level]
      adapted = adjust_complexity_for_user_preference(adapted)
    end

    # Adjust hierarchy recommendation based on user behavior
    if @user_preferences[:hierarchy_preference]
      adapted = adjust_hierarchy_for_user_preference(adapted)
    end

    # Add user-specific execution recommendations
    adapted[:execution_recommendations] = enhance_recommendations_for_user(
      adapted[:execution_recommendations]
    )

    adapted
  end

  def adjust_complexity_for_user_preference(analysis)
    user_typical_complexity = @user_preferences[:preferred_complexity_level]
    current_complexity = analysis[:complexity_score]

    # If user typically handles higher complexity, don't over-simplify
    if user_typical_complexity >= 7 && current_complexity >= 6
      analysis[:execution_recommendations][:notes] ||= []
      analysis[:execution_recommendations][:notes] << "Based on your history, you handle complex projects well"
    end

    # If user typically prefers simpler approaches, suggest breaking down
    if user_typical_complexity <= 4 && current_complexity >= 7
      analysis[:execution_recommendations][:specific_recommendations] ||= []
      analysis[:execution_recommendations][:specific_recommendations] <<
        "Consider breaking this into smaller, separate lists based on your preferences"
    end

    analysis
  end

  def adjust_hierarchy_for_user_preference(analysis)
    if @user_preferences[:hierarchy_preference] == "prefers_flat" &&
       analysis[:hierarchical_needs][:needs_hierarchy]

      analysis[:hierarchical_needs][:alternative_suggestion] =
        "Consider using categories or tags instead of hierarchy based on your typical approach"
    end

    if @user_preferences[:hierarchy_preference] == "prefers_hierarchical" &&
       !analysis[:hierarchical_needs][:needs_hierarchy] &&
       analysis[:complexity_score] >= 5

      analysis[:hierarchical_needs][:user_preference_suggestion] =
        "You typically prefer hierarchical organization - consider organizing this into phases"
    end

    analysis
  end

  def enhance_recommendations_for_user(base_recommendations)
    enhanced = base_recommendations || {}

    # Add user-specific timing recommendations
    if @user_preferences[:completion_patterns]
      enhanced[:timing_suggestions] = generate_timing_suggestions
    end

    # Add size recommendations based on user patterns
    if @user_preferences[:typical_list_size]
      enhanced[:list_size_guidance] = generate_size_guidance
    end

    enhanced
  end

  def learn_from_analysis(user_message, analysis)
    # Store this analysis for future learning (simplified for demo)
    learning_data = {
      message_length: user_message.length,
      detected_complexity: analysis[:complexity_score],
      had_location_elements: analysis[:location_analysis][:has_location_elements],
      was_hierarchical: analysis[:hierarchical_needs][:needs_hierarchy],
      timestamp: Time.current
    }

    # In a real implementation, this would update ML models or preference weights
    @logger.debug "Learning from analysis: #{learning_data}"
  end

  def analyze_user_complexity_preference(user_lists)
    complexity_scores = user_lists.map do |list|
      list.metadata.dig("complexity_analysis", "score")
    end.compact

    return nil if complexity_scores.empty?

    complexity_scores.sum.to_f / complexity_scores.length
  end

  def calculate_typical_list_size(user_lists)
    sizes = user_lists.map(&:list_items_count)
    return nil if sizes.empty?

    sizes.sum.to_f / sizes.length
  end

  def analyze_hierarchy_preference(user_lists)
    hierarchical_count = user_lists.count do |list|
      list.metadata.dig("creation_type") == "hierarchical_planning"
    end

    total_analyzed = user_lists.count
    return nil if total_analyzed == 0

    hierarchy_percentage = hierarchical_count.to_f / total_analyzed

    if hierarchy_percentage >= 0.6
      "prefers_hierarchical"
    elsif hierarchy_percentage <= 0.2
      "prefers_flat"
    else
      "mixed"
    end
  end

  def analyze_completion_patterns(user_lists)
    completed_lists = user_lists.where(status: :completed)
    return nil if completed_lists.empty?

    # Analyze time patterns, completion rates, etc.
    {
      average_completion_time: calculate_average_completion_time(completed_lists),
      completion_rate: completed_lists.count.to_f / user_lists.count
    }
  end

  def calculate_average_completion_time(completed_lists)
    durations = completed_lists.map do |list|
      if list.updated_at && list.created_at
        (list.updated_at - list.created_at) / 1.day
      end
    end.compact

    return nil if durations.empty?
    durations.sum / durations.length
  end

  def generate_timing_suggestions
    completion_patterns = @user_preferences[:completion_patterns]
    return nil unless completion_patterns

    avg_time = completion_patterns[:average_completion_time]
    return nil unless avg_time

    case avg_time
    when 0..1
      "Based on your history, you typically complete projects within a day"
    when 1..7
      "You usually take about a week to complete similar projects"
    when 7..30
      "Your typical project completion time is 1-4 weeks"
    else
      "You tend to work on longer-term projects (1+ months)"
    end
  end

  def generate_size_guidance
    typical_size = @user_preferences[:typical_list_size]
    return nil unless typical_size

    case typical_size
    when 0..5
      "You typically prefer shorter, focused lists (under 5 items)"
    when 5..15
      "Your typical list size is 5-15 items"
    when 15..30
      "You're comfortable with detailed lists (15-30 items)"
    else
      "You work well with comprehensive lists (30+ items)"
    end
  end
end
