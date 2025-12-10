# API Endpoints - RAG & Search

## Search Endpoints

### GET `/search` - Web Search Interface
**Description**: Interactive search page with UI

**Parameters**:
- `q` (string, required): Search query
- `limit` (integer, optional): Max results (default: 20)

**Example**:
```
GET /search?q=implement+authentication
GET /search?q=meeting&limit=5
```

**Response**: HTML page with formatted results

---

### GET `/search.json` - JSON Search Results
**Description**: API endpoint for search results in JSON format

**Parameters**:
- `q` (string, required): Search query
- `limit` (integer, optional): Max results (default: 20)

**Example**:
```bash
curl "http://localhost:3000/search.json?q=test&limit=10"
```

**Response**:
```json
{
  "query": "test",
  "results": [
    {
      "id": "uuid-123",
      "type": "List",
      "title": "Test Planning",
      "description": "Plan the test suite",
      "url": "/lists/uuid-123",
      "created_at": "2025-01-15T10:00:00Z",
      "updated_at": "2025-01-15T10:00:00Z"
    },
    {
      "id": "uuid-456",
      "type": "ListItem",
      "title": "Write unit tests",
      "description": "Add tests for auth flow",
      "url": "/lists/uuid-parent/items/uuid-456",
      "created_at": "2025-01-15T09:00:00Z",
      "updated_at": "2025-01-15T09:00:00Z"
    }
  ],
  "count": 2
}
```

**Status Codes**:
- `200 OK` - Search successful
- `401 Unauthorized` - User not authenticated
- `400 Bad Request` - Missing query parameter

---

## Internal Service APIs

These are Ruby service classes used internally. Not HTTP endpoints.

### SearchService

**Purpose**: Hybrid search (vector + full-text) across multiple models

```ruby
# Call the service
result = SearchService.call(
  query: "implement auth",
  user: current_user,
  models: [List, ListItem, Comment],  # Optional, defaults to all
  limit: 20,                           # Optional
  use_vector: true                     # Optional, use embeddings
)

# Check result
if result.success?
  results = result.data  # Array of records
else
  errors = result.errors
end
```

**Parameters**:
- `query` (String): Search text
- `user` (User): User performing search (for org scoping)
- `models` (Array): Classes to search (default: all)
- `limit` (Integer): Max results (default: 20)
- `use_vector` (Boolean): Use vector search (default: true)

**Returns**:
- Success: Array of matching records (List, ListItem, Comment, Tag)
- Failure: Error messages

**Features**:
- Automatic org boundary enforcement
- Fallback to keyword-only if embeddings unavailable
- Respects public/private list visibility
- Comments inherit parent visibility

---

### RagService

**Purpose**: Assemble context from search results for LLM

```ruby
# Call the service
rag_result = RagService.call(
  query: "what am I working on?",
  user: current_user,
  chat: current_user.current_chat,  # Optional
  max_context_items: 5              # Optional
)

# Check result
if rag_result.success?
  data = rag_result.data
  # {
  #   prompt: "...[enhanced prompt with context]...",
  #   context_sources: [
  #     { source_number: 1, type: "List", title: "...", url: "/lists/..." },
  #     ...
  #   ],
  #   search_results: [...],
  #   context_count: 3
  # }
else
  errors = rag_result.errors
end
```

**Parameters**:
- `query` (String): User's question/request
- `user` (User): User context
- `chat` (Chat, optional): Chat object (not used yet)
- `max_context_items` (Integer): Top-K results to include (default: 5)

**Returns**:
```ruby
{
  prompt: String,              # Full prompt with context for LLM
  context_sources: Array,      # Source attribution data
  search_results: Array,       # Raw search results
  context_count: Integer       # Number of context items included
}
```

**Features**:
- Searches user's accessible lists/items/comments
- Generates system prompt with context
- Formats source attribution with URLs
- Always-on (no toggling required)

---

### EmbeddingGenerationService

**Purpose**: Generate vector embeddings for content

```ruby
# Generate embedding for a record
result = EmbeddingGenerationService.call(list_record)

# Check result
if result.success?
  updated_record = result.data
else
  errors = result.errors
end
```

**Parameters**:
- `record` (ActiveRecord): Object to embed (List, ListItem, Comment, Tag)

**Returns**:
```ruby
{
  success: Boolean,
  data: record,           # Updated record with embedding
  errors: Array,          # Error messages if failed
  message: String         # Human-readable message
}
```

**Features**:
- Calls OpenAI text-embedding-3-small API
- Truncates content to safe limits
- Updates embedding + timestamp
- Logs all API interactions

**Automatic Triggers**:
- Called automatically when record is created
- Called automatically when content changes
- Scheduled via Solid Queue background jobs

---

## Model Methods

### SearchableEmbeddable (Concern)

Added to List, ListItem, Comment, and Tag models.

```ruby
list = List.first

# Class methods
List.needs_embedding          # Scope: records awaiting embedding
List.stale_embeddings         # Scope: embeddings older than 30 days
List.semantic_search(query, user)  # Search via SearchService

# Instance methods
list.embedding_stale?         # Boolean: is embedding old?
list.embedding_generated?     # Boolean: has embedding?
list.content_for_embedding    # String: text to embed
list.content_changed?         # Boolean: did content change?
```

### Full-Text Search

Available on List, ListItem, Comment, and Tag:

```ruby
# Full-text search (keyword matching)
lists = List.search_by_keyword("implement")
items = ListItem.search_by_keyword("urgent")
comments = Comment.search_by_keyword("approved")
tags = ActsAsTaggableOn::Tag.search_by_keyword("important")
```

---

## Integration Examples

### Example 1: Search from Controller

```ruby
class SearchController < ApplicationController
  def search
    results = SearchService.call(
      query: params[:q],
      user: current_user,
      limit: 20
    )

    if results.success?
      @results = results.data
      render :results
    else
      flash[:error] = results.errors.join(", ")
      redirect_back fallback_location: root_path
    end
  end
end
```

### Example 2: RAG in Chat Controller

```ruby
class Chat::ChatController < ApplicationController
  def create_message
    @message_content = params[:message]

    # Get RAG context
    rag_result = RagService.call(
      query: @message_content,
      user: current_user
    )

    if rag_result.success?
      # Use enhanced prompt for LLM
      llm_prompt = rag_result.data[:prompt]
      sources = rag_result.data[:context_sources]
    else
      # Fallback to plain message
      llm_prompt = @message_content
      sources = []
    end

    # Send to LLM and create message...
  end
end
```

### Example 3: Manual Embedding Generation

```ruby
# In Rails console or rake task

# Generate embeddings for all records
[List, ListItem, Comment].each do |model|
  model.needs_embedding.each do |record|
    EmbeddingGenerationJob.perform_later(model.name, record.id)
  end
end

# Or synchronously (for testing):
list = List.first
EmbeddingGenerationService.call(list)
```

### Example 4: Search with Custom Limit

```ruby
# Search with specific limit
result = SearchService.call(
  query: "urgent tasks",
  user: current_user,
  limit: 5  # Only 5 results
)

# Or via HTTP
GET /search.json?q=urgent+tasks&limit=5
```

---

## Error Handling

### Search Errors

```ruby
result = SearchService.call(query: "", user: nil)

if result.failure?
  puts result.errors  # ["Query cannot be blank"]
  puts result.message # "Search failed"
end
```

### RAG Errors

```ruby
result = RagService.call(query: "test", user: nil)

if result.failure?
  puts result.errors  # ["User not found"]
  # Fall back to plain message
end
```

---

## Performance Notes

### Search
- Vector search: ~50-100ms (optimized with IVFFLAT)
- Full-text search: ~20-50ms (GIN indexed)
- Hybrid: ~100-150ms combined
- Results cached in Solid Cache for 15 minutes

### Embeddings
- Generation: ~500ms per item (API call)
- Queued async via Solid Queue
- Bulk operations: process in background
- Cost: ~$0.0002 per embedding

### Memory
- In-memory caching per request (single query)
- No persistent cache beyond Solid Cache
- Large result sets paginated via Pagy (not yet integrated)

---

## Testing

### Test Searches

```ruby
# In RSpec
it "finds accessible lists" do
  user = create(:user)
  list = create(:list, owner: user)

  result = SearchService.call(
    query: list.title,
    user: user
  )

  expect(result.success?).to be_truthy
  expect(result.data).to include(list)
end
```

### Test RAG

```ruby
it "assembles context for RAG" do
  user = create(:user)
  list = create(:list, owner: user, title: "Test List")

  result = RagService.call(
    query: "test",
    user: user
  )

  expect(result.success?).to be_truthy
  expect(result.data[:context_count]).to be > 0
  expect(result.data[:prompt]).to include("Test List")
end
```

---

## Monitoring

### Check Embedding Status
```ruby
# Rails console
List.where(embedding: nil).count           # Records awaiting embeddings
List.where(requires_embedding_update: true).count  # Stale embeddings
ActsAsTaggableOn::Tag.needs_embedding.count       # Tags needing embedding
```

### Check Recent Searches
```bash
# In logs
tail -f log/development.log | grep "Search query"
```

### Monitor API Usage
```ruby
# Logs show all OpenAI calls
tail -f log/development.log | grep "Generating embedding"
```

---

## Troubleshooting

### Search Returns Nothing

**Check**:
1. Has content been embedded? `List.first.embedding.present?`
2. Is user in the same org? `user.in_organization?(list.organization)`
3. Is API key configured? `ENV['OPENAI_API_KEY'].present?`

**Solution**:
```ruby
# Manually trigger embedding
list = List.first
EmbeddingGenerationService.call(list)

# Check embedding was created
list.reload
list.embedding.present? # Should be true
```

### RAG Returns Empty Context

**Check**:
1. Does user have accessible records? `user.lists.count`
2. Have embeddings been generated? `user.lists.where.not(embedding: nil).count`

**Solution**:
```ruby
# Ensure records have embeddings
user.lists.each do |list|
  EmbeddingGenerationJob.perform_later(List.name, list.id)
end
```

---

## Future Endpoints (Planned)

- `POST /search/save` - Save search queries
- `GET /search/history` - User's search history
- `GET /admin/search/stats` - Search analytics
- `PATCH /embeddings/regenerate` - Manual regeneration

---

## Rate Limiting

Currently: None implemented

**Recommended**:
- 100 searches/minute per user
- 1000 searches/minute per IP
- Consider implementing if needed

---

## Caching Strategy

**Search Results**: 15 minutes (Solid Cache)
- Cached by: `(user_id, organization_id, query)`
- Invalidated on: List/Item/Comment changes

**Embeddings**: 30 days (database)
- Regenerated if older or content changes
- Fallback: Keyword search if embedding missing

---

## Production Checklist

- [ ] OpenAI API key configured
- [ ] Solid Queue running for background jobs
- [ ] Database indexed (migrations run)
- [ ] Search endpoint tested with production data
- [ ] RAG integrated into chat (if using)
- [ ] Error monitoring configured (Sentry, etc.)
- [ ] API rate limiting configured
- [ ] Search analytics enabled

---

