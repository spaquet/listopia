class RagService < ApplicationService
  # RAG (Retrieval-Augmented Generation) service
  # Assembles context from user's accessible content for LLM prompts
  # Always-on context assembly for chat interactions

  def initialize(query:, user:, chat: nil, max_context_items: 5)
    @query = query
    @user = user
    @chat = chat
    @max_context_items = max_context_items
  end

  def call
    return failure(errors: ["User not found"]) unless @user
    return failure(errors: ["Query cannot be blank"]) if @query.blank?

    # Search for relevant context
    search_result = SearchService.call(
      query: @query,
      user: @user,
      models: [List, ListItem, Comment],
      limit: @max_context_items
    )

    return failure(errors: ["Search failed"]) unless search_result.success?

    context_items = build_context(search_result.data)
    enhanced_prompt = build_prompt(context_items)

    success(data: {
      prompt: enhanced_prompt,
      context_sources: format_sources(search_result.data),
      search_results: search_result.data,
      context_count: context_items.length
    })
  rescue StandardError => e
    Rails.logger.error("RAG context assembly failed: #{e.class} - #{e.message}")
    failure(errors: [e.message], message: "RAG context assembly failed")
  end

  private

  def build_context(results)
    results.map do |record|
      case record
      when List
        {
          type: "List",
          title: record.title,
          content: record.description.presence || "No description",
          record: record
        }
      when ListItem
        {
          type: "Item",
          title: record.title,
          content: record.description.presence || "No description",
          list_title: record.list.title,
          record: record
        }
      when Comment
        {
          type: "Comment",
          title: "Comment by #{record.user.name}",
          content: record.content,
          record: record
        }
      end
    end.compact
  end

  def build_prompt(context)
    context_text = context.each_with_index.map do |item, idx|
      title_section = item[:type] == "Item" ? " (in #{item[:list_title]})" : ""
      "[#{idx + 1}] **#{item[:type]}: #{item[:title]}**#{title_section}\n#{item[:content]}"
    end.join("\n\n")

    system_prompt = <<~PROMPT
      You are a helpful assistant for a task and list management application.
      You have access to the user's lists, items, and comments.

      When answering questions, prioritize using the context from the user's lists and items.
      If citing information from the context, reference the source number (e.g., "[Source 1]").

      If the context doesn't contain relevant information, say so and provide general advice.
      Be conversational and helpful.
    PROMPT

    if context.empty?
      context_text = "No relevant context found for this query."
    end

    prompt = <<~PROMPT
      #{system_prompt}

      User's Context:
      #{context_text}

      User Question: #{@query}
    PROMPT

    prompt.strip
  end

  def format_sources(results)
    results.each_with_index.map do |record, idx|
      {
        source_number: idx + 1,
        type: record.class.name,
        title: format_title(record),
        url: record_url(record)
      }
    end
  end

  def format_title(record)
    case record
    when List
      record.title
    when ListItem
      "#{record.title} (in #{record.list.title})"
    when Comment
      "Comment on #{record.commentable.class.name}"
    else
      "Unknown"
    end
  end

  def record_url(record)
    case record
    when List
      "/lists/#{record.id}"
    when ListItem
      "/lists/#{record.list_id}/items/#{record.id}"
    when Comment
      "/#{record.commentable_type.tableize}/#{record.commentable_id}#comment-#{record.id}"
    end
  end
end
