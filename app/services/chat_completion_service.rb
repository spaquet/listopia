# app/services/chat_completion_service.rb
#
# Service for handling chat message processing using RubyLLM
# Integrates with RubyLLM 1.9+ for unified LLM provider support
# Supports OpenAI, Anthropic Claude, Google Gemini, and more

class ChatCompletionService < ApplicationService
  def initialize(chat, user_message, context = nil)
    @chat = chat
    @user_message = user_message
    @context = context || ChatContext.new(
      chat: chat,
      user: user_message.user,
      organization: chat.organization,
      location: :dashboard
    )
  end

  def call
    return failure(errors: ["Chat not found"]) unless @chat
    return failure(errors: ["User message not found"]) unless @user_message

    begin
      # Get or determine the model to use
      model = @chat.metadata["model"] || default_model

      # Build message history for context
      message_history = build_message_history(model)

      # Get system prompt based on context
      system_prompt = @context.system_prompt

      # Call RubyLLM with the message history
      response = call_llm(model, system_prompt, message_history)

      return failure(errors: ["LLM call failed"]) if response.blank?

      # Create assistant message
      assistant_message = Message.create_assistant(
        chat: @chat,
        content: response
      )

      # Update chat with last message time
      @chat.update(last_message_at: Time.current)

      success(data: assistant_message)
    rescue StandardError => e
      Rails.logger.error("Chat completion failed: #{e.class} - #{e.message}")
      failure(errors: [e.message], message: "Failed to generate response")
    end
  end

  private

  # Determine the default LLM model and provider
  def default_model
    "gpt-4o-mini"  # OpenAI default - can be configured per organization/user
  end

  # Parse model string to extract provider and model name
  # Examples: "gpt-4o-mini", "claude-3-sonnet", "gemini-pro"
  def parse_model(model_string)
    case model_string
    when /^gpt-/
      { provider: :openai, model: model_string }
    when /^claude-/
      { provider: :anthropic, model: model_string }
    when /^gemini-/
      { provider: :google, model: model_string }
    when /^llama-/
      { provider: :fireworks, model: model_string }
    else
      { provider: :openai, model: model_string }
    end
  end

  # Build message history from recent messages in the chat
  def build_message_history(model)
    recent_messages = @chat.messages.ordered.last(20)

    messages = recent_messages.map do |msg|
      {
        role: msg.role.to_s,
        content: msg.content
      }
    end

    # Add current user message if not already in history
    messages.push({
      role: "user",
      content: @user_message.content
    })

    messages
  end

  # Call RubyLLM with the provided messages
  def call_llm(model, system_prompt, message_history)
    model_config = parse_model(model)

    # Create RubyLLM::Chat instance
    llm_chat = RubyLLM::Chat.new(
      provider: model_config[:provider],
      model: model_config[:model]
    )

    # Set additional options if supported
    llm_chat.temperature = 0.7 if llm_chat.respond_to?(:temperature=)
    llm_chat.max_tokens = 2000 if llm_chat.respond_to?(:max_tokens=)

    # Add system prompt
    if system_prompt.present?
      llm_chat.add_message(role: "system", content: system_prompt)
    end

    # Add message history (excluding current message since we'll add separately)
    message_history[0...-1].each do |msg|
      llm_chat.add_message(role: msg[:role], content: msg[:content])
    end

    # Add current user message
    llm_chat.add_message(role: "user", content: @user_message.content)

    # Get completion
    response = llm_chat.complete

    # Extract response content
    extract_response_content(response)
  rescue => e
    Rails.logger.error("RubyLLM error: #{e.class} - #{e.message}")
    Rails.logger.error(e.backtrace.join("\n"))
    nil
  end

  # Extract the assistant's response from RubyLLM response object
  def extract_response_content(response)
    Rails.logger.debug("RubyLLM response class: #{response.class}")
    Rails.logger.debug("RubyLLM response: #{response.inspect}")

    case response
    when String
      response
    when Hash
      response["content"] || response[:content] || response.to_s
    else
      # Try to get content/message method if available
      if response.respond_to?(:content)
        response.content
      elsif response.respond_to?(:message)
        response.message
      elsif response.respond_to?(:text)
        response.text
      else
        response.to_s
      end
    end
  end
end
