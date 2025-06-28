# app/services/mcp_service.rb
class McpService
  include ActiveModel::Model
  include ActiveModel::Attributes

  attr_accessor :user, :context, :chat

  def initialize(user:, context: {}, chat: nil)
    @user = user
    @context = context
    @chat = chat || user.current_chat
    @tools = McpTools.new(user, context)
  end

  def process_message(message_content)
    start_time = Time.current

    # Ensure user is authenticated
    raise AuthorizationError, "User must be authenticated" unless @user

    # Check rate limits
    rate_limiter = McpRateLimiter.new(@user)
    rate_limiter.check_rate_limit!

    # Validate message length
    if message_content.length > Rails.application.config.mcp.max_message_length
      raise ValidationError, "Message is too long (max #{Rails.application.config.mcp.max_message_length} characters)"
    end

    begin
      # Use RubyLLM's Rails integration through the chat model
      model = Rails.application.config.mcp.model
      @chat.update!(model_id: model) if @chat.model_id.blank?

      # Add system instructions if context requires it
      if needs_system_instructions?
        @chat.with_instructions(build_system_instructions, replace: true)
      end

      # Configure tools
      if @tools.available_tools.any?
        @tools.available_tools.each do |tool|
          @chat.with_tool(tool)
        end
      end

      # Use RubyLLM's ask method
      response = @chat.ask(message_content)
      assistant_content = response.content

      # Increment rate limit counters after successful processing
      rate_limiter.increment_counters!

      assistant_content

    rescue RubyLLM::Error => e
      Rails.logger.error "RubyLLM Error: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      "I apologize, but I encountered an error processing your request. Please try again."
    end

  rescue McpRateLimiter::RateLimitError => e
    e.message
  rescue ValidationError => e
    e.message
  rescue => e
    Rails.logger.error "MCP Error: #{e.message}"
    Rails.logger.error e.backtrace.join("\n")
    "I apologize, but I encountered an error processing your request. Please try again."
  end

  private

  def needs_system_instructions?
    @context.present? || @chat.messages.where(role: "system").empty?
  end

  def build_system_instructions
    instructions = []

    instructions << "You are an AI assistant integrated with Listopia, a collaborative list management application."
    instructions << "You can help users manage their lists, create items, update tasks, and collaborate with others."

    # Enhanced planning context instructions
    instructions << <<~PLANNING
      IMPORTANT: Listopia is fundamentally a planning and organization tool. When users mention ANY of the following, you should immediately create a list with relevant items:

      🎯 PLANNING CONTEXTS (always create lists):
      - Vacation/Travel planning (flights, hotels, itinerary, packing)
      - Project management (tasks, milestones, deliverables)
      - Goal setting (objectives, steps, milestones)
      - Event planning (weddings, parties, meetings)
      - Shopping (grocery, retail, supplies)
      - Moving/Relocation (packing, utilities, address changes)
      - Job search (resume, applications, interviews)
      - Learning/Education (courses, materials, schedule)
      - Health/Fitness (workouts, diet, appointments)
      - Financial planning (budgets, savings, investments)
      - Home improvement (tasks, materials, contractors)
      - Business strategy (initiatives, analysis, execution)

      📋 AUTOMATIC LIST CREATION RULES:
      1. When user mentions planning ANYTHING, create a list immediately using create_planning_list
      2. Always include a descriptive title and helpful description
      3. Auto-generate relevant planning items based on the context
      4. Use appropriate item types (task, goal, milestone, reminder)
      5. Set reasonable priorities (high for critical items, medium for important, low for nice-to-have)

      💡 EXAMPLES:
      - "Plan vacation to Argentina" → Create "Argentina Vacation Planning" list with flights, hotels, itinerary items
      - "Organize sprint for Q1" → Create "Q1 Sprint Planning" list with scope, tasks, milestones
      - "Need to quit smoking" → Create "Quit Smoking Plan" list with strategy steps, milestones, support items
      - "Planning wedding" → Create "Wedding Planning" list with venue, catering, invitations, etc.

      🚀 PROACTIVE PLANNING:
      - Don't wait for the user to say "create a list"
      - Recognize planning intent and act immediately
      - Suggest additional items that might be helpful
      - Ask follow-up questions to enhance the plan
    PLANNING

    if @context.present?
      instructions << "Current context: #{build_context_message}"
    end

    if @tools.available_tools.any?
      instructions << "You have access to tools that can help you:"
      @tools.available_tools.each do |tool|
        instructions << "- #{tool.class.name}: #{tool.class.description}"
      end
      instructions << "Use these tools proactively when appropriate to help the user accomplish their goals."
    end

    instructions << "Always be helpful, accurate, and respect user permissions."
    instructions << "Remember: When in doubt about whether something involves planning, CREATE A LIST!"

    instructions.join("\n\n")
  end

  def build_context_message
    return "No additional context available." if @context.blank?

    context_parts = []

    if @context["page"]
      context_parts << "User is currently on page: #{@context['page']}"
    end

    if @context["list_id"]
      context_parts << "User is viewing list: #{@context['list_title']} (ID: #{@context['list_id']})"
      context_parts << "List has #{@context['items_count']} items, #{@context['completed_count']} completed"
      context_parts << "User #{@context['is_owner'] ? 'owns' : 'collaborates on'} this list"
      context_parts << "User #{@context['can_collaborate'] ? 'can edit' : 'can only view'} this list"
    end

    if @context["total_lists"]
      context_parts << "User has access to #{@context['total_lists']} total lists"
    end

    context_parts.join(". ")
  end

  class AuthorizationError < StandardError; end
  class ValidationError < StandardError; end
end
