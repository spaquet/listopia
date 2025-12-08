# Quick Start: RAG + Semantic Search

## 🚀 Get Started in 3 Steps

### Step 1: Run Migrations
```bash
bundle exec rails db:migrate
```

This creates:
- Vector columns (embeddings) on Lists, ListItems, Comments, Tags
- Full-text search indexes
- pgvector extension in PostgreSQL

**Time**: ~30 seconds

### Step 2: Try Search
```bash
rails s
# Visit: http://localhost:3000/search
# Search for something in your lists
```

Search automatically works because:
- New records trigger embedding generation via Solid Queue
- Keyword search works as fallback if embeddings are pending
- Results are organization-scoped (secure)

**Time**: ~5 minutes

### Step 3: Integrate RAG into Chat (Optional)
See `Chat Integration` section below for chat + RAG setup.

**Time**: ~15 minutes

---

## 📚 What Each Component Does

### SearchService
```ruby
# Search Lists, ListItems, Comments, Tags with org scoping
result = SearchService.call(
  query: "implement authentication",
  user: current_user,
  limit: 10
)
# => Returns accessible results sorted by relevance
```

### RagService
```ruby
# Assemble context from search results for LLM
rag = RagService.call(
  query: "what am I working on?",
  user: current_user
)
# => Returns {
#      prompt: "...[context]...User query: ...",
#      context_sources: [...],
#      context_count: 3
#    }
```

### EmbeddingGenerationService
```ruby
# Called automatically on create/update
# Or manually for bulk operations
result = EmbeddingGenerationService.call(list_record)
```

---

## 🔧 Chat Integration

### Simple: Add RAG to Existing Messages

In your chat controller where you create messages:

```ruby
class Chat::ChatController < ApplicationController
  def create_message
    @chat = current_user.chats.find(params[:chat_id])
    user_message = params[:message]

    # Assemble RAG context
    rag_result = RagService.call(
      query: user_message,
      user: current_user
    )

    if rag_result.success?
      # Use enhanced prompt with context
      llm_prompt = rag_result.data[:prompt]

      # Store sources for UI display
      sources = rag_result.data[:context_sources]
    else
      # Fallback to plain message if RAG fails
      llm_prompt = user_message
      sources = []
    end

    # Send to LLM and save message
    @message = @chat.messages.create!(
      content: user_message,
      metadata: { rag_sources: sources }
    )

    # ... rest of your message creation logic
  end
end
```

### Display Sources in Chat UI

In your message view:

```erb
<div class="message">
  <%= message.content %>

  <% if message.metadata[:rag_sources].present? %>
    <div class="sources text-sm text-gray-500">
      <strong>Sources:</strong>
      <ul>
        <% message.metadata[:rag_sources].each do |source| %>
          <li>
            <%= link_to source[:title], source[:url] %>
            <span class="text-xs">(<%= source[:type] %>)</span>
          </li>
        <% end %>
      </ul>
    </div>
  <% end %>
</div>
```

---

## 🎯 Use Cases

### Search Feature
Users can now:
- Search all their lists, items, comments
- Find by semantic meaning (not just keywords)
- See public lists in results
- Click to view context

**URL**: `/search?q=your+query`

### RAG Chat Feature
The app now can:
- Pull relevant context from user's lists when answering questions
- Show sources so users know where info came from
- Provide more accurate, personalized responses
- Work offline (keyword-only fallback)

---

## 📊 Monitoring

### Check Embedding Status
```ruby
# Rails console
List.needs_embedding.count          # Lists awaiting embedding
List.stale_embeddings.count         # Lists with old embeddings
ListItem.where(embedding: nil).count # Items without embeddings
```

### Watch Background Jobs
```ruby
# Via Solid Queue dashboard (if available)
# Or check logs:
tail -f log/development.log | grep "EmbeddingGenerationJob"
```

### View Search Performance
```ruby
# Logs show all searches:
# "Search query: 'implement' | Results: 5 | Time: 124ms"
tail -f log/development.log | grep "Search query"
```

---

## 💡 Tips

### For Development
- Embeddings generate automatically (no manual setup needed)
- Search works immediately even without embeddings (keyword fallback)
- Test with: `SearchService.call(query: "test", user: current_user)`

### For Testing
```ruby
# In tests, disable async embedding generation
# Add to spec_helper.rb:
Solid Queue job queue disabled in tests
# Or use: perform_enqueued_jobs { create(:list, title: "..") }
```

### For Production
- Monitor OpenAI API costs (very cheap!)
- Set up error alerts for failed embeddings
- Consider caching frequent searches
- Batch regenerate stale embeddings nightly

---

## ❓ FAQ

**Q: Do I need to do anything to generate embeddings?**
A: No! They're generated automatically when you create/update content.

**Q: Does search work without OpenAI API key?**
A: Yes! It falls back to keyword-only search if API is unavailable.

**Q: Can I search other users' content?**
A: No. Search is scoped to user's organizations only (secure by default).

**Q: How much does it cost?**
A: Extremely cheap. ~$0.07/month for 100 users with 5,000 items.

**Q: Can I disable embeddings?**
A: Not easily built-in, but you can comment out scheduling in `SearchableEmbeddable`.

**Q: Does RAG always have to be on?**
A: Currently yes. You could add a toggle to Chat model if desired.

---

## 🔗 Learn More

- **Architecture**: See `IMPLEMENTATION_PLAN.md`
- **Status**: See `RAG_SEARCH_IMPLEMENTATION_STATUS.md`
- **Code**:
  - Services: `/app/services/`
  - Models: `/app/models/concerns/searchable_embeddable.rb`
  - Views: `/app/views/search/`

---

## 🐛 Common Issues

### "Search returns nothing"
1. Check if content has embeddings: `List.first.embedding.present?`
2. Wait for background jobs to complete
3. Verify OpenAI API key is set: `ENV['OPENAI_API_KEY']`

### "Embeddings not generating"
1. Check Solid Queue is running: `rails solid_queue:start`
2. Check logs for errors: `tail log/development.log`
3. Manually trigger: `EmbeddingGenerationJob.perform_now(List.name, list_id)`

### "Cross-org data showing up"
This shouldn't happen (SearchService filters by org). If it does, check `accessible?` method.

---

## ✅ Next: You're Ready!

Run migrations and start searching. RAG integration is optional but recommended for better chat experience.

Questions? Check the code comments - they're detailed!
