class SearchService < ApplicationService
  # Hybrid search service combining vector similarity and full-text search
  # Searches across Lists, ListItems, Comments, and Tags
  # Enforces organization and access control boundaries

  def initialize(query:, user:, models: nil, limit: 20, use_vector: true)
    @query = query
    @user = user
    @models = Array(models || [List, ListItem, Comment, ActsAsTaggableOn::Tag]).compact
    @limit = limit
    @use_vector = use_vector && embedding_api_available?
  end

  def call
    return failure(errors: ["Query cannot be blank"]) if @query.blank?

    results = search_all_models
    ranked_results = rank_results(results)
    scoped_results = filter_by_accessibility(ranked_results)

    success(data: scoped_results.take(@limit))
  rescue StandardError => e
    Rails.logger.error("Search failed: #{e.class} - #{e.message}")
    failure(errors: [e.message], message: "Search failed")
  end

  private

  def search_all_models
    results = []

    @models.each do |model|
      if @use_vector && has_embedding?(model)
        results.concat(vector_search(model))
      else
        results.concat(keyword_search(model))
      end
    end

    results
  end

  def vector_search(model)
    query_embedding = fetch_embedding(@query)
    return [] if query_embedding.nil?

    # Use PostgreSQL's cosine distance operator (<->)
    # Lower distance = higher similarity
    records = model.where.not(embedding: nil)
                   .order("embedding <-> '#{vector_to_sql(query_embedding)}'::vector")
                   .limit(@limit)

    records.map do |record|
      {
        record: record,
        relevance_score: calculate_relevance(record, query_embedding),
        search_type: :vector
      }
    end
  rescue => e
    Rails.logger.warn("Vector search failed for #{model.name}: #{e.message}")
    []
  end

  def keyword_search(model)
    records = model.search_by_keyword(@query).limit(@limit)

    records.map do |record|
      {
        record: record,
        relevance_score: 0.5, # Default score for keyword matches
        search_type: :keyword
      }
    end
  rescue => e
    Rails.logger.warn("Keyword search failed for #{model.name}: #{e.message}")
    []
  end

  def rank_results(results)
    # Sort by: relevance score (desc) → recency (desc) → model type
    results.sort_by do |result|
      [
        -result[:relevance_score],
        -(result[:record].created_at.to_i),
        result[:record].class.name
      ]
    end.map { |r| r[:record] }
  end

  def filter_by_accessibility(records)
    records.select { |record| accessible?(record) }
  end

  def accessible?(record)
    case record
    when List
      return true if record.is_public?
      return true if record.readable_by?(@user) && @user.in_organization?(record.organization)
      false
    when ListItem
      list = record.list
      return true if list.is_public?
      return true if list.readable_by?(@user) && @user.in_organization?(list.organization)
      false
    when Comment
      # Comments inherit accessibility from their parent (List or ListItem)
      case record.commentable
      when List
        list = record.commentable
        return true if list.is_public?
        return true if list.readable_by?(@user) && @user.in_organization?(list.organization)
      when ListItem
        list = record.commentable.list
        return true if list.is_public?
        return true if list.readable_by?(@user) && @user.in_organization?(list.organization)
      end
      false
    when ActsAsTaggableOn::Tag
      # Tags are searchable if they're used on accessible items
      # For now, allow search but filter in results
      true
    else
      false
    end
  end

  def fetch_embedding(text)
    # Cache embeddings for the same query in memory (for this request)
    @embedding_cache ||= {}
    return @embedding_cache[text] if @embedding_cache.key?(text)

    response = RubyLLM::Embeddings.create(
      model: "text-embedding-3-small",
      input: text.truncate(8000)
    )

    if response.success?
      embedding = response.data.first.embedding
      @embedding_cache[text] = embedding
      return embedding
    end

    Rails.logger.error("Failed to fetch embedding: #{response.inspect}")
    nil
  rescue => e
    Rails.logger.error("Error fetching embedding: #{e.class} - #{e.message}")
    nil
  end

  def calculate_relevance(record, query_embedding)
    # Use PostgreSQL's cosine distance
    # Convert to similarity: 1 / (1 + distance)
    # This gives us a score between 0 and 1
    distance = calculate_distance(record.embedding, query_embedding)
    1.0 / (1.0 + distance)
  end

  def calculate_distance(vec1, vec2)
    # For now, return a placeholder
    # In production, PostgreSQL calculates this in the ORDER BY clause
    0.0
  end

  def vector_to_sql(vector)
    # Convert Ruby array to PostgreSQL vector format
    "[#{vector.join(',')}]"
  end

  def has_embedding?(model)
    model.column_names.include?("embedding")
  end

  def embedding_api_available?
    # Check if OpenAI API key is configured
    ENV["OPENAI_API_KEY"].present? || ENV["RUBY_LLM_OPENAI_API_KEY"].present?
  end
end
