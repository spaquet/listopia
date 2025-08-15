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
    @chat = chat
    @logger = Rails.logger
  end

  # Main analysis method using LLM-first approach
  def analyze_complexity(user_message, additional_context: {})
    @logger.info "TaskComplexityAnalyzer: Starting LLM-based analysis for user #{@user.id}"

    begin
      # Primary: Use LLM for intelligent analysis
      llm_analysis = perform_llm_analysis(user_message, additional_context)

      if llm_analysis[:success]
        @logger.debug "LLM analysis successful"
        return enhance_llm_analysis(llm_analysis[:data], user_message)
      else
        @logger.warn "LLM analysis failed: #{llm_analysis[:error]}"
      end

    rescue => e
      @logger.error "LLM analysis error: #{e.message}"
    end

    # Fallback: Use keyword-based heuristic analysis
    @logger.info "Using fallback heuristic analysis"
    fallback_analysis(user_message, additional_context)
  end

  # Quick complexity check using hybrid approach
  def quick_complexity_check(user_message)
    # Try LLM quick analysis first
    quick_llm_result = perform_quick_llm_analysis(user_message)

    if quick_llm_result[:success]
      return quick_llm_result[:data]
    end

    # Fallback to heuristic
    quick_heuristic_analysis(user_message)
  end

  private

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

  def build_llm_analysis_prompt(user_message, additional_context)
    context_info = build_context_string(additional_context)

    <<~PROMPT
      You are an expert task complexity analyzer for a list management application.
      Analyze the following user request for complexity factors and classification.

      USER REQUEST: "#{user_message}"

      CONTEXT INFORMATION:
      #{context_info}

      Please analyze this request across multiple dimensions and respond with JSON:

      {
        "complexity_score": 1-10,
        "complexity_level": "simple|moderate|complex|very_complex",
        "location_analysis": {
          "has_location_elements": boolean,
          "multiple_locations": boolean,
          "travel_related": boolean,
          "location_types": ["city", "venue", "remote", "etc"],
          "complexity_reasoning": "explain why"
        },
        "multi_step_analysis": {
          "has_multi_step_elements": boolean,
          "estimated_step_count": number,
          "sequential_dependencies": boolean,
          "parallel_tasks_possible": boolean,
          "complexity_reasoning": "explain the process flow"
        },
        "external_service_analysis": {
          "needs_external_services": boolean,
          "service_categories": {
            "booking": boolean,
            "communication": boolean,
            "research": boolean,
            "commerce": boolean,
            "integration": boolean
          },
          "service_reasoning": "explain what services and why"
        },
        "list_type_classification": {
          "primary_type": "professional|personal|mixed",
          "confidence_percentage": 0-100,
          "type_indicators": ["list of factors that influenced classification"],
          "classification_reasoning": "explain the classification decision"
        },
        "hierarchical_needs": {
          "needs_hierarchy": boolean,
          "estimated_depth": 1-5,
          "hierarchy_type": "phases|categories|nested_tasks|timeline",
          "hierarchy_reasoning": "explain why hierarchical structure is or isn't needed"
        },
        "language_and_cultural_context": {
          "detected_language": "language code or 'mixed'",
          "cultural_context": "business|personal|academic|etc",
          "regional_considerations": "any location or culture specific factors"
        },
        "planning_context_compatibility": {
          "suggested_context": "recommended planning context type",
          "fits_existing_patterns": boolean,
          "extension_needed": boolean,
          "context_reasoning": "explain context recommendation"
        }
      }

      ANALYSIS GUIDELINES:
      - Consider linguistic nuances, not just keywords
      - Detect implied complexity (e.g., "coordinate" implies multi-step)
      - Consider cultural context (business vs personal indicators vary by culture)
      - Think about practical execution challenges
      - Consider dependencies and resource requirements
      - Be language-agnostic in your analysis

      Respond ONLY with valid JSON. No explanatory text outside the JSON structure.
    PROMPT
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

  # Quick LLM analysis for real-time UI
  def perform_quick_llm_analysis(user_message)
    analysis_chat = create_analysis_chat

    quick_prompt = <<~PROMPT
      Quickly analyze this task request and respond with JSON:

      REQUEST: "#{user_message}"

      {
        "complexity_score": 1-10,
        "requires_planning": boolean,
        "list_type": "professional|personal|mixed",
        "multi_location": boolean,
        "external_services": boolean,
        "quick_reasoning": "brief explanation"
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

  # Enhanced LLM analysis with additional processing
  def enhance_llm_analysis(llm_data, user_message)
    # Add integration compatibility assessment
    llm_data[:planning_context_compatibility] = assess_planning_context_compatibility_llm(
      llm_data[:planning_context_compatibility][:suggested_context]
    )

    # Add execution recommendations
    llm_data[:execution_recommendations] = generate_execution_recommendations(llm_data)

    # Add risk assessment
    llm_data[:risk_assessment] = assess_complexity_risks(llm_data)

    llm_data
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

  # Utility methods
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
