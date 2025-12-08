# app/services/prompt_injection_detector.rb
#
# Detects and analyzes potential prompt injection attacks in user messages.
# Implements multiple detection strategies to identify:
# - Prompt rewriting attempts ("ignore previous instructions")
# - Role switching ("act as", "pretend you are")
# - Context escape attempts ("disregard the system prompt")
# - Jailbreak keywords ("unrestricted", "no limitations")
# - Suspicious encoding (Base64, HTML entities, Unicode tricks)

class PromptInjectionDetector
  # High-confidence injection patterns
  INJECTION_PATTERNS = {
    prompt_rewriting: [
      /ignore\s+(?:previous|earlier|prior|above)\s+(?:instructions|prompts?|directives)/i,
      /forget\s+(?:previous|earlier|everything|above)/i,
      /start\s+over/i,
      /new\s+(?:conversation|chat|session)/i,
      /disregard\s+(?:previous|above)/i
    ],

    role_switching: [
      /^(?:you\s+)?are\s+now/i,
      /act\s+as\s+(?:a\s+)?(?:an\s+)?/i,
      /pretend\s+(?:you\s+)?are\s+(?:a\s+)?(?:an\s+)?/i,
      /assume\s+(?:the\s+)?(?:role|persona)\s+of/i,
      /be\s+the\s+/i
    ],

    context_escape: [
      /outside\s+(?:the\s+)?system/i,
      /bypass(?:ing|ed)?\s+(?:the\s+)?(?:system\s+)?(?:prompt|guidelines)/i,
      /disregard\s+(?:the\s+)?system\s+prompt/i,
      /ignore\s+(?:the\s+)?guidelines?/i,
      /override\s+(?:system|safety)/i,
      /no\s+longer\s+subject\s+to/i
    ],

    jailbreak_keywords: [
      /unrestricted/i,
      /without\s+(?:limitations|restrictions|constraints)/i,
      /anything\s+goes/i,
      /no\s+filter/i,
      /no\s+restrictions?/i,
      /don't\s+refuse/i,
      /must\s+(?:always\s+)?comply/i
    ],

    prompt_injection_meta: [
      /\[(?:system|instruction|prompt|command|SYSTEM|INSTRUCTION)\]/,
      /```prompt/i,
      /<<<SYSTEM>>>/i,
      /\{START_JAILBREAK\}/i
    ]
  }.freeze

  # Suspicious patterns that might indicate obfuscation
  SUSPICIOUS_PATTERNS = {
    base64_encoded: [
      /^[A-Za-z0-9+\/]{20,}={0,2}$/,
      /base64/i
    ],

    html_entities: [
      /&#\d{4,5};/,       # Numeric entities
      /&#x[0-9a-f]{4,}/i, # Hex entities
      /&[a-z]+;/i        # Named entities (too broad, combined with content check)
    ],

    unicode_tricks: [
      /\p{Cyrillic}/,  # Cyrillic - commonly used for obfuscation
      /\p{Arabic}/,    # Arabic
      /\p{Devanagari}/ # Devanagari
    ],

    command_injection: [
      /`.*`/,           # Shell backticks
      /\$\{.*\}/,       # Template variables
      /\$\(.*\)/,       # Command substitution
      /<%.*%>/         # ERB templates
    ]
  }.freeze

  # Risk level thresholds
  RISK_THRESHOLDS = {
    low: 0..2,
    medium: 3..5,
    high: 6..Float::INFINITY
  }.freeze

  def initialize(message:, context: nil)
    @message = message.to_s.strip
    @context = context
    @detected_patterns = []
    @risk_score = 0
  end

  # Main detection method
  # Returns: { detected: true/false, risk_level: "low"/"medium"/"high", patterns: [], risk_score: 0..10 }
  def call
    return { detected: false, risk_level: "low", patterns: [], risk_score: 0 } if @message.blank?

    check_injection_patterns
    check_suspicious_patterns
    check_prompt_confusion
    check_repetition_attacks

    risk_level = calculate_risk_level
    detected = risk_level != "low"

    {
      detected: detected,
      risk_level: risk_level,
      patterns: @detected_patterns,
      risk_score: @risk_score
    }
  end

  private

  # Check for known injection patterns
  def check_injection_patterns
    INJECTION_PATTERNS.each do |category, patterns|
      patterns.each do |pattern|
        if @message.match?(pattern)
          @detected_patterns << "#{category}: #{pattern.source[0..40]}"
          @risk_score += 2
        end
      end
    end
  end

  # Check for suspicious encoding/obfuscation
  def check_suspicious_patterns
    SUSPICIOUS_PATTERNS.each do |category, patterns|
      patterns.each do |pattern|
        if @message.match?(pattern)
          @detected_patterns << "suspicious_#{category}"
          @risk_score += 1
        end
      end
    end
  end

  # Detect prompt vs data confusion attacks (meta-prompt-injection)
  def check_prompt_confusion
    # Multiple sections separated by delimiters often indicate prompt injection
    delimiter_count = @message.count("\n---") + @message.count("====") + @message.count("----")
    if delimiter_count >= 2
      @detected_patterns << "multiple_prompt_sections"
      @risk_score += 1
    end

    # Very long messages with repeated patterns
    if @message.length > 5000 && @message.scan(/^#+/).length >= 3
      @detected_patterns << "suspicious_structure_length"
      @risk_score += 1
    end
  end

  # Detect repetition attacks (repeating the same instruction many times)
  def check_repetition_attacks
    # Check for repeated lines
    lines = @message.split("\n")
    if lines.length > 1
      line_counts = Hash.new(0)
      lines.each { |line| line_counts[line] += 1 }

      # If any line appears 5+ times, it's suspicious
      if line_counts.values.any? { |count| count >= 5 }
        @detected_patterns << "repetition_attack"
        @risk_score += 2
      end
    end

    # Check for repeated keywords
    words = @message.downcase.split(/\s+/)
    if words.length > 20
      word_counts = Hash.new(0)
      words.each { |word| word_counts[word] += 1 }

      # If any word appears 10+ times and is a suspicious keyword
      if word_counts.select { |word, count| count >= 10 && SUSPENSION_KEYWORDS.include?(word) }.any?
        @detected_patterns << "keyword_repetition_attack"
        @risk_score += 1
      end
    end
  end

  # Calculate overall risk level based on score
  def calculate_risk_level
    RISK_THRESHOLDS.each do |level, range|
      return level.to_s if range.include?(@risk_score)
    end
    "high"
  end

  # Keywords that might indicate jailbreak when repeated
  SUSPENSION_KEYWORDS = %w[ignore forget disregard bypass override system prompt instructions].freeze
end
