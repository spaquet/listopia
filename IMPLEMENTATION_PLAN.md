# RAG + Semantic Search Implementation Plan

## Overview
Implement integrated Retrieval-Augmented Generation (RAG) and semantic search across Lists, ListItems, Comments, and Tags using PostgreSQL's pgvector extension (already available in your Docker image) plus strategic full-text search for keyword matching.

## Architecture Design

### Core Components

#### 1. Vector Embeddings Strategy
- **Embedding Model**: Use `ruby_llm` gem (already in Gemfile) to call OpenAI's `text-embedding-3-small` (cost-effective, 1536 dimensions)
- **Storage**: PostgreSQL `vector` column type (pgvector 0.8.0 ready)
- **Scope**: Embed content from Lists, ListItems, Comments, and Tags
- **Update Strategy**:
  - Generate embeddings on create/update via background jobs (Solid Queue)
  - Stale embedding handling via timestamp comparison

#### 2. Full-Text Search Integration
- **Tool**: `pg_search` gem (already in Gemfile)
- **Usage**: Keyword matching for exact/fuzzy searches alongside semantic search
- **Benefits**:
  - Better for exact phrase matching
  - Complements vector similarity for hybrid search
  - Faster for simple keyword queries

#### 3. Search Implementation
- **Hybrid Search**: Combine vector similarity + full-text search
- **Ranking**: Weight results by relevance (vector similarity + text match + recency)
- **Scope Control**: All queries filtered by user's accessible organizations/teams
- **Caching**: Use Solid Cache for frequent searches (user's org scope)

#### 4. RAG Implementation
- **Chat Integration**: Leverage existing `Chat` and `Message` models
- **Context Assembly**:
  - Search user's accessible lists/items/comments
  - Rank by relevance (similarity + recency)
  - Assemble top-K results as context
  - Pass to existing `ruby_llm` integration
- **Authorization**: Enforce org boundaries at query stage
- **Prompt Engineering**: Provide source references from RAG results

---

## Database Changes

### Migration 1: Add Vector Columns

```ruby
# File: db/migrate/TIMESTAMP_add_embedding_vectors.rb

class AddEmbeddingVectors < ActiveRecord::Migration[8.0]
  def change
    # Enable pgvector extension
    enable_extension 'vector'

    # Add columns to Lists
    add_column :lists, :embedding, :vector, limit: 1536
    add_index :lists, :embedding, using: :ivfflat, opclass: :vector_cosine_ops
    add_column :lists, :embedding_generated_at, :datetime

    # Add columns to ListItems
    add_column :list_items, :embedding, :vector, limit: 1536
    add_index :list_items, :embedding, using: :ivfflat, opclass: :vector_cosine_ops
    add_column :list_items, :embedding_generated_at, :datetime

    # Add columns to Comments
    add_column :comments, :embedding, :vector, limit: 1536
    add_index :comments, :embedding, using: :ivfflat, opclass: :vector_cosine_ops
    add_column :comments, :embedding_generated_at, :datetime

    # Track which embeddings need regeneration
    add_column :lists, :requires_embedding_update, :boolean, default: false
    add_column :list_items, :requires_embedding_update, :boolean, default: false
    add_column :comments, :requires_embedding_update, :boolean, default: false
  end
end
```

### Migration 2: Add Full-Text Search Columns

```ruby
# File: db/migrate/TIMESTAMP_add_fulltext_search_support.rb

class AddFulltextSearchSupport < ActiveRecord::Migration[8.0]
  def change
    # Add search document columns for pg_search
    add_column :lists, :search_document, :tsvector
    add_index :lists, :search_document, using: :gin

    add_column :list_items, :search_document, :tsvector
    add_index :list_items, :search_document, using: :gin

    add_column :comments, :search_document, :tsvector
    add_index :comments, :search_document, using: :gin
  end
end
```

---

## Models Changes

### 1. SearchableEmbeddable Concern

```ruby
# File: app/models/concerns/searchable_embeddable.rb

module SearchableEmbeddable
  extend ActiveSupport::Concern

  included do
    has_one_attached :embedding_model, dependent: :destroy

    validates :embedding_generated_at, allow_nil: true

    scope :needs_embedding, -> { where(requires_embedding_update: true).or(where(embedding: nil)) }
    scope :stale_embeddings, ->(hours = 30 * 24) {
      where("embedding_generated_at < ?", hours.hours.ago).or(where(embedding: nil))
    }

    before_save :mark_embedding_stale, if: :content_changed?
    after_commit :schedule_embedding_generation, on: [:create, :update]
  end

  class_methods do
    def semantic_search(query, user, limit: 10)
      # This method will be implemented in SearchService
      SearchService.call(query: query, user: user, model: self, limit: limit)
    end
  end

  private

  def mark_embedding_stale
    self.requires_embedding_update = true
  end

  def schedule_embedding_generation
    return unless requires_embedding_update?
    return if Rails.env.test?

    EmbeddingGenerationJob.set(wait: 1.second).perform_later(self.class.name, id)
  end

  def content_changed?
    # Override in each model for relevant fields
    false
  end
end
```

### 2. List Model Updates

```ruby
# In app/models/list.rb
include SearchableEmbeddable
include PgSearch::Model

pg_search_scope :search_by_keyword,
  against: { title: 'A', description: 'B' },
  using: { tsearch: { prefix: true } }

def content_for_embedding
  "#{title}\n\n#{description}"
end

private

def content_changed?
  title_changed? || description_changed?
end
```

### 3. ListItem Model Updates

```ruby
# In app/models/list_item.rb
include SearchableEmbeddable
include PgSearch::Model

pg_search_scope :search_by_keyword,
  against: { title: 'A', description: 'B' },
  using: { tsearch: { prefix: true } }

def content_for_embedding
  "#{title}\n\n#{description}"
end

private

def content_changed?
  title_changed? || description_changed?
end
```

### 4. Comment Model Updates

```ruby
# In app/models/comment.rb
include SearchableEmbeddable
include PgSearch::Model

pg_search_scope :search_by_keyword,
  against: { content: 'A' },
  using: { tsearch: { prefix: true } }

def content_for_embedding
  content
end

private

def content_changed?
  content_changed?
end
```

---

## Services

### 1. Embedding Generation Service

```ruby
# File: app/services/embedding_generation_service.rb

class EmbeddingGenerationService < ApplicationService
  def initialize(record)
    @record = record
  end

  def call
    return failure(errors: ["Record not found"]) unless @record

    content = @record.content_for_embedding
    return failure(errors: ["No content to embed"]) if content.blank?

    embedding_vector = fetch_embedding(content)
    return failure(errors: ["Failed to generate embedding"]) if embedding_vector.nil?

    @record.update_columns(
      embedding: embedding_vector,
      embedding_generated_at: Time.current,
      requires_embedding_update: false
    )

    success(data: @record)
  rescue StandardError => e
    failure(errors: [e.message], message: "Embedding generation failed")
  end

  private

  def fetch_embedding(text)
    # Truncate to avoid token limits (3-small handles ~8191 tokens)
    truncated_text = text.truncate(8000)

    response = RubyLLM::Embeddings.create(
      model: "text-embedding-3-small",
      input: truncated_text
    )

    response.data.first.embedding if response.success?
  end
end
```

### 2. Search Service (Hybrid)

```ruby
# File: app/services/search_service.rb

class SearchService < ApplicationService
  def initialize(query:, user:, models: [List, ListItem, Comment], limit: 20, use_vector: true)
    @query = query
    @user = user
    @models = Array(models)
    @limit = limit
    @use_vector = use_vector
  end

  def call
    results = search_all_models
    ranked_results = rank_results(results)
    scoped_results = filter_by_accessibility(ranked_results)

    success(data: scoped_results.take(@limit))
  rescue StandardError => e
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

    model.where.not(embedding: nil)
         .order("embedding <-> '#{query_embedding}'::vector")
         .limit(@limit)
         .map { |record| [record, cosine_similarity(record.embedding, query_embedding)] }
  end

  def keyword_search(model)
    model.search_by_keyword(@query)
         .limit(@limit)
         .map { |record| [record, 0.0] }
  end

  def rank_results(results)
    results.sort_by { |record, score| [-score, -record.created_at.to_i] }
           .map { |record, _| record }
  end

  def filter_by_accessibility(results)
    results.select { |record| accessible?(record) }
  end

  def accessible?(record)
    case record
    when List
      record.readable_by?(@user) &&
      (@user.in_organization?(record.organization) || record.is_public?)
    when ListItem
      record.list.readable_by?(@user) &&
      (@user.in_organization?(record.list.organization) || record.list.is_public?)
    when Comment
      # Comments inherit accessibility from commentable
      case record.commentable
      when List
        record.commentable.readable_by?(@user) &&
        (@user.in_organization?(record.commentable.organization) || record.commentable.is_public?)
      when ListItem
        record.commentable.list.readable_by?(@user) &&
        (@user.in_organization?(record.commentable.list.organization) || record.commentable.list.is_public?)
      else
        false
      end
    else
      false
    end
  end

  def fetch_embedding(text)
    RubyLLM::Embeddings.create(
      model: "text-embedding-3-small",
      input: text.truncate(8000)
    ).data.first.embedding rescue nil
  end

  def has_embedding?(model)
    model.columns_hash.key?("embedding")
  end

  def cosine_similarity(vec1, vec2)
    # PostgreSQL returns <-> operator result (distance, not similarity)
    # Higher value = more dissimilar, so we invert: 1 / (1 + distance)
    1.0 / (1.0 + (vec1 - vec2).norm)
  end
end
```

### 3. RAG Service

```ruby
# File: app/services/rag_service.rb

class RagService < ApplicationService
  def initialize(query:, user:, chat: nil, max_context_items: 5)
    @query = query
    @user = user
    @chat = chat
    @max_context_items = max_context_items
  end

  def call
    # Search for relevant context
    search_result = SearchService.call(
      query: @query,
      user: @user,
      models: [List, ListItem, Comment],
      limit: @max_context_items
    )

    return failure(errors: ["Search failed"]) unless search_result.success?

    context = build_context(search_result.data)
    enhanced_prompt = build_prompt(context)

    success(data: {
      prompt: enhanced_prompt,
      context_sources: format_sources(search_result.data),
      search_results: search_result.data
    })
  rescue StandardError => e
    failure(errors: [e.message], message: "RAG context assembly failed")
  end

  private

  def build_context(results)
    results.map do |record|
      case record
      when List
        { type: "List", title: record.title, content: record.description }
      when ListItem
        { type: "ListItem", title: record.title, content: record.description }
      when Comment
        { type: "Comment", content: record.content }
      end
    end.compact
  end

  def build_prompt(context)
    context_text = context.each_with_index.map do |item, idx|
      "[Source #{idx + 1} - #{item[:type]}]\n#{item[:title]}: #{item[:content]}\n\n"
    end.join

    <<~PROMPT
      You are an assistant helping a user with their lists and tasks.

      Based on the following context from the user's lists and items:

      #{context_text}

      Original user query: #{@query}

      Provide a helpful response using the context provided.
      If citing information from context, reference the source numbers.
    PROMPT
  end

  def format_sources(results)
    results.each_with_index.map do |record, idx|
      {
        source: idx + 1,
        type: record.class.name,
        title: record.respond_to?(:title) ? record.title : "Comment",
        link: record_path(record)
      }
    end
  end

  def record_path(record)
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
```

---

## Background Jobs

### Embedding Generation Job

```ruby
# File: app/jobs/embedding_generation_job.rb

class EmbeddingGenerationJob < ApplicationJob
  queue_as :default

  sidekiq_options lock: { type: :until_executed, on_conflict: :log }

  def perform(model_name, record_id)
    model = model_name.constantize
    record = model.find(record_id)

    result = EmbeddingGenerationService.call(record)

    return if result.success?

    Rails.logger.error("Embedding generation failed for #{model_name} #{record_id}: #{result.errors.join(', ')}")
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn("Record not found: #{model_name} #{record_id}")
  end
end
```

---

## Controllers & Views

### Search Controller

```ruby
# File: app/controllers/search_controller.rb

class SearchController < ApplicationController
  before_action :authenticate_user!

  def index
    @query = params[:q]
    @results = if @query.present?
      SearchService.call(
        query: @query,
        user: current_user,
        limit: params[:limit] || 20
      )
    else
      ApplicationService::Result.success(data: [])
    end

    respond_to do |format|
      format.html
      format.turbo_stream
      format.json { render json: @results.data }
    end
  end
end
```

### RAG Chat Integration

```ruby
# In existing Chat controller, add RAG context:

def create_message
  @chat = current_user.chats.find(params[:chat_id])
  @message = @chat.messages.build(content: params[:content])

  # Add RAG context if enabled
  if @chat.use_rag?
    rag_result = RagService.call(
      query: params[:content],
      user: current_user,
      chat: @chat
    )

    if rag_result.success?
      @message.metadata ||= {}
      @message.metadata[:rag_sources] = rag_result.data[:context_sources]
      @message.metadata[:rag_context] = rag_result.data[:prompt]
    end
  end

  # Pass to LLM with RAG context if available
  @message.save
  # ... send to LLM
end
```

---

## Gems to Add

```ruby
# Gemfile additions (already has pg_search, ruby_llm)

# Already installed:
# gem "pg_search"
# gem "ruby_llm"
# gem "solid_queue" (for background jobs)

# Migration: None needed! pgvector is already in PostgreSQL Docker image
```

---

## Implementation Phases

### Phase 1: Foundation (1-2 days)
- [ ] Add database migrations (vectors + full-text)
- [ ] Create `SearchableEmbeddable` concern
- [ ] Update List, ListItem, Comment models
- [ ] Create `EmbeddingGenerationService`
- [ ] Create `EmbeddingGenerationJob`
- [ ] Test embedding generation end-to-end

### Phase 2: Search (1-2 days)
- [ ] Create `SearchService` (hybrid search)
- [ ] Build `SearchController`
- [ ] Create search UI (Turbo Streams friendly)
- [ ] Add search results view with source attribution
- [ ] Test authorization boundary enforcement

### Phase 3: RAG Chat (1 day)
- [ ] Create `RagService`
- [ ] Integrate RAG into existing Chat functionality
- [ ] Add RAG metadata to messages
- [ ] Display source attribution in chat
- [ ] Add chat setting to toggle RAG on/off

### Phase 4: Refinements & Performance (1 day)
- [ ] Add caching for frequent searches
- [ ] Optimize vector indexes (IVFFLAT tuning)
- [ ] Batch embedding generation for bulk operations
- [ ] Monitor and log performance
- [ ] Add admin dashboard for embedding status

---

## Authorization & Access Control

### Key Principles
1. **All searches filtered by user's organizations**: User can only search content in orgs they belong to
2. **Respect list visibility**: Private lists only searchable by collaborators
3. **Public lists**: Visible in global search if `is_public?`
4. **Comments**: Inherit visibility from parent (List/ListItem)
5. **Teams**: Search scoped to user's teams within org

### Implementation
- `SearchService` calls `filter_by_accessibility()` on all results
- Use `policy_scope(Model)` when available
- Tests for cross-org data leakage

---

## Testing Strategy

```ruby
# RSpec examples

describe SearchService do
  it "returns results accessible by user" do
    # User in Org A searches
    # Should find: accessible lists in Org A + public lists
    # Should NOT find: lists in Org B
  end

  it "respects list collaboration permissions" do
    # Private list with no collaboration returns nothing
    # List with user as collaborator returns results
  end

  it "respects comment visibility through parent" do
    # Comments on private lists not visible
    # Comments on public lists visible
  end
end

describe EmbeddingGenerationService do
  it "generates embedding for list content" do
    list = create(:list, title: "Test List", description: "Test Description")
    result = EmbeddingGenerationService.call(list)

    expect(result).to be_success
    expect(list.reload.embedding).to be_present
    expect(list.embedding.is_a?(Array)).to be_truthy
  end
end

describe RagService do
  it "assembles context from top search results" do
    user = create(:user)
    list = create(:list, owner: user)
    item = create(:list_item, list: list)

    result = RagService.call(query: "test", user: user)

    expect(result).to be_success
    expect(result.data[:prompt]).to include(item.title)
    expect(result.data[:context_sources]).to be_present
  end
end
```

---

## Performance Considerations

### Database Queries
- **Vector indexes**: Use IVFFLAT for similarity search (pgvector recommended)
- **Full-text indexes**: GIN index on `search_document`
- **IVFFlat Parameters**:
  - `probes`: Start with 10 (default), adjust based on recall needs
  - `lists`: Start with 100, increase for larger datasets

### Caching
- Cache embedding API responses in `Solid Cache` (5 mins)
- Cache search results scoped by (user_id, organization_id, query) - 15 mins
- Cache RAG context assembly (2 hours)

### Background Jobs
- Use Solid Queue's prioritization
- Batch embedding generation for bulk updates
- Implement circuit breaker for embedding API failures

### Monitoring
- Track embedding generation time
- Monitor search latency (vector vs full-text)
- Alert on failed embedding jobs

---

## Migration Path from Current State

1. **Backward Compatibility**: Existing searches continue via pg_search
2. **Gradual Rollout**:
   - First: Add vector columns (non-breaking)
   - Second: Queue background jobs for existing records
   - Third: Launch new search UI alongside existing
   - Fourth: Migrate users to new search

3. **Data Cleanup**:
   - Migrate tags if using acts-as-taggable-on (already in Gemfile)
   - Update Comments to include organization context for proper scoping

---

## Next Steps for User

1. **Review this plan**: Approve architecture and approach
2. **Clarify embeddings scope**: Should we embed tags separately?
3. **RAG chat toggles**: Per-chat setting or per-user?
4. **Performance SLOs**: Expected search response times?
5. **Scope priorities**: Implement all models at once or start with Lists only?

