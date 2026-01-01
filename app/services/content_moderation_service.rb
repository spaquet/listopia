# app/services/content_moderation_service.rb
#
# Wraps OpenAI's Moderation API via RubyLLM to check message content.
# Detects and flags harmful content including:
# - Hate speech and harassment
# - Self-harm content
# - Sexual content (especially minors)
# - Violence and graphic violence
#
# Returns moderation scores and flags for each category.
# Only creates ModerationLog if content is flagged.

class ContentModerationService
  # OpenAI moderation categories
  CATEGORIES = {
    hate: "Hate",
    hate_threatening: "Hate (Threatening)",
    harassment: "Harassment",
    harassment_threatening: "Harassment (Threatening)",
    self_harm: "Self-harm",
    self_harm_intent: "Self-harm (Intent)",
    self_harm_instructions: "Self-harm (Instructions)",
    sexual: "Sexual content",
    sexual_minors: "Sexual content (Minors)",
    violence: "Violence",
    violence_graphic: "Violence (Graphic)"
  }.freeze

  def initialize(content:, user: nil, chat: nil)
    @content = content.to_s.strip
    @user = user
    @chat = chat
  end

  # Check if content is flagged by moderation
  # Returns: { flagged: true/false, categories: { cat => true/false }, scores: { cat => 0.0..1.0 }, error: nil }
  def call
    return { flagged: false, categories: {}, scores: {}, error: nil } if @content.blank?

    result = call_openai_moderation

    if result.is_a?(Hash) && result[:error].present?
      Rails.logger.warn("Moderation API error: #{result[:error]}")
      return result
    end

    # Log if flagged
    log_moderation_action(result) if result[:flagged]

    result
  rescue StandardError => e
    Rails.logger.error("ContentModerationService error: #{e.message}")
    {
      flagged: false,
      categories: {},
      scores: {},
      error: "Moderation check failed: #{e.message}"
    }
  end

  private

  # Call OpenAI moderation API via RubyLLM
  def call_openai_moderation
    unless ENV["LISTOPIA_USE_MODERATION"] == "true"
      return { flagged: false, categories: {}, scores: {}, error: nil }
    end

    unless ENV["OPENAI_API_KEY"].present? || ENV["RUBY_LLM_OPENAI_API_KEY"].present?
      Rails.logger.warn("OpenAI API key not configured for moderation")
      return { flagged: false, categories: {}, scores: {}, error: nil }
    end

    # Call RubyLLM moderation
    response = RubyLLM::Moderation.create(text: @content)

    # Parse response
    parse_moderation_response(response)
  rescue StandardError => e
    Rails.logger.error("OpenAI moderation API call failed: #{e.message}")
    {
      flagged: false,
      categories: {},
      scores: {},
      error: "API call failed: #{e.message}"
    }
  end

  # Parse RubyLLM moderation response
  def parse_moderation_response(response)
    # RubyLLM returns: { results: [{ flagged: bool, categories: {}, category_scores: {} }] }
    result = response.is_a?(Hash) ? response[:results]&.first : response&.first

    return default_response if result.blank?

    flagged = result[:flagged] || result["flagged"] || false
    categories = extract_categories(result)
    scores = extract_scores(result)

    {
      flagged: flagged,
      categories: categories,
      scores: scores,
      error: nil
    }
  end

  # Extract category flags from moderation result
  def extract_categories(result)
    cats = result[:categories] || result["categories"] || {}
    # Convert to our category names
    CATEGORIES.keys.each_with_object({}) do |key, hash|
      # RubyLLM key format: "hate" or with underscore variants
      api_key = key.to_s.gsub("_", "-")
      hash[key] = cats[api_key] || cats[key.to_s] || false
    end
  end

  # Extract category scores from moderation result
  def extract_scores(result)
    scores = result[:category_scores] || result["category_scores"] || {}
    # Convert to our category names
    CATEGORIES.keys.each_with_object({}) do |key, hash|
      api_key = key.to_s.gsub("_", "-")
      score = scores[api_key] || scores[key.to_s] || 0.0
      hash[key] = score.to_f
    end
  end

  # Create moderation log if content is flagged
  def log_moderation_action(result)
    return unless @chat.present? && @user.present?

    flagged_categories = result[:categories].select { |_k, v| v }.keys
    return if flagged_categories.empty?

    # Determine primary violation type from categories
    violation_type = categorize_violation(flagged_categories)

    ModerationLog.create!(
      chat: @chat,
      user: @user,
      organization: @chat.organization,
      violation_type: violation_type,
      action_taken: :logged,
      detected_patterns: flagged_categories.map(&:to_s),
      moderation_scores: result[:scores],
      details: "OpenAI moderation flagged: #{flagged_categories.join(', ')}"
    )
  rescue StandardError => e
    Rails.logger.error("Failed to create moderation log: #{e.message}")
  end

  # Categorize violation based on which categories were flagged
  def categorize_violation(flagged_categories)
    case flagged_categories
    when *flagged_categories.include?(:self_harm), *flagged_categories.include?(:self_harm_intent), *flagged_categories.include?(:self_harm_instructions)
      :self_harm
    when *flagged_categories.include?(:sexual_minors)
      :sexual_content
    when *flagged_categories.include?(:sexual)
      :sexual_content
    when *flagged_categories.include?(:violence_graphic)
      :violence
    when *flagged_categories.include?(:violence)
      :violence
    when *flagged_categories.include?(:harassment_threatening), *flagged_categories.include?(:harassment)
      :harassment
    when *flagged_categories.include?(:hate_threatening)
      :hate_speech
    when *flagged_categories.include?(:hate)
      :hate_speech
    else
      :other
    end
  end

  # Default response when moderation is disabled
  def default_response
    { flagged: false, categories: {}, scores: {}, error: nil }
  end
end
