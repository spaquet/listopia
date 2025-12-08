# Getting Started Checklist

Follow this checklist to get RAG + Semantic Search running in your app.

---

## Pre-Flight ✈️

- [ ] You have the latest code pulled
- [ ] You have an OpenAI API key (for embeddings)
- [ ] Your `.env` file has `OPENAI_API_KEY` or `RUBY_LLM_OPENAI_API_KEY` set
- [ ] You've read `QUICK_START_RAG_SEARCH.md`

**Time**: 5 minutes

---

## Database Setup 🗄️

### Step 1: Run Migrations
```bash
bundle exec rails db:migrate
```

**What it does**:
- Creates `embedding` vector columns on Lists, ListItems, Comments, Tags
- Creates IVFFLAT indexes for fast similarity search
- Creates `search_document` TSVECTOR columns for full-text search
- Creates GIN indexes on search documents
- Enables pgvector extension

**Check**:
```bash
# Verify migrations ran
bundle exec rails db:migrate:status | tail -3
# Should show:
# up     20251208050100  Add embedding vectors
# up     20251208050101  Add fulltext search support
```

**Time**: 30 seconds

---

## Search Feature Testing 🔍

### Step 2: Start the Server
```bash
rails s
```

### Step 3: Test Search UI
1. Visit `http://localhost:3000/search`
2. Try searching for something in your lists
3. See results appear

**Expected behavior**:
- Empty state showing "Search your content"
- Search box focused and ready
- Results appear as you type (or after clicking Search)
- Results show title, description, and metadata
- Click "View" to go to the item

**If search returns nothing**:
1. Check if you have any lists/items
2. Create a test list with title "Test Search" and description "This is a test"
3. Search again in a few seconds (embeddings generate async)
4. If still nothing, check logs: `tail -f log/development.log | grep -i embedding`

**Time**: 5-10 minutes

---

## Optional: RAG Chat Integration 💬

### Step 4: Add RAG to Chat (if you use chat)

In your **chat message creation** code, add context assembly:

**File**: `app/controllers/chat/chat_controller.rb`

```ruby
def create_message
  @chat = current_user.chats.find(params[:chat_id])
  user_message = params[:message]

  # NEW: Assemble RAG context
  rag_result = RagService.call(
    query: user_message,
    user: current_user
  )

  if rag_result.success?
    llm_prompt = rag_result.data[:prompt]
    sources = rag_result.data[:context_sources]
  else
    llm_prompt = user_message
    sources = []
  end

  # Create message with sources metadata
  @message = @chat.messages.create!(
    content: user_message,
    metadata: { rag_sources: sources }
  )

  # Send llm_prompt to your LLM instead of user_message
  # This includes relevant context from their lists/items

  # ... rest of your logic
end
```

### Step 5: Display Sources in Chat UI (Optional)

In your **message view**, add:

**File**: `app/views/chats/_message.html.erb`

```erb
<div class="message">
  <%= message.content %>

  <% if message.metadata.dig(:rag_sources).present? %>
    <div class="sources text-xs text-gray-500 mt-2 pl-4 border-l border-gray-300">
      <strong>Sources:</strong>
      <ul class="list-disc list-inside">
        <% message.metadata[:rag_sources].each do |source| %>
          <li>
            <%= link_to source[:title], source[:url], target: "_blank", class: "text-blue-600" %>
            <span class="text-gray-400">(<%= source[:type] %>)</span>
          </li>
        <% end %>
      </ul>
    </div>
  <% end %>
</div>
```

**Time**: 10-15 minutes

---

## Verify Everything Works ✅

### Check 1: Search is Indexed
```ruby
# In Rails console
List.first.embedding.present?        # Should be true (after a few seconds)
ListItem.first.embedding.present?    # Should be true
```

### Check 2: Search Returns Results
```bash
curl "http://localhost:3000/search.json?q=test"
# Should return JSON with results
```

### Check 3: RAG Generates Context
```ruby
# In Rails console
user = User.first
rag_result = RagService.call(query: "what am I working on?", user: user)
puts rag_result.data[:prompt]  # Should show context with lists/items
```

**All checks pass?** ✨ You're done!

---

## Monitoring 📊

### Check Embedding Status
```ruby
# In Rails console

# Records still awaiting embeddings
List.needs_embedding.count
ListItem.needs_embedding.count
Comment.needs_embedding.count

# Records with embeddings
List.where.not(embedding: nil).count

# Stale embeddings (older than 30 days)
List.stale_embeddings.count
```

### Watch Background Jobs
```bash
# View Solid Queue job status
# (if you have Solid Queue admin set up)

# Or check logs for job execution
tail -f log/development.log | grep "EmbeddingGenerationJob"
```

### Monitor API Costs
All embedding API calls are logged. You can estimate costs:
- `text-embedding-3-small`: ~$0.02 per 1M tokens
- Average item: ~200 tokens
- Cost per 1000 items: ~$0.004

Very cheap!

---

## Common Issues & Fixes 🔧

### "Search returns nothing"

**Cause**: Embeddings haven't been generated yet

**Fix**:
```bash
# Wait 10 seconds for background jobs to process
sleep 10
# Try searching again
```

Or manually trigger:
```ruby
List.first.update(title: "Force Embedding")  # Triggers background job
```

### "OpenAI API error"

**Cause**: Missing API key

**Fix**:
```bash
# Check if key is set
echo $OPENAI_API_KEY

# If empty, add to .env
OPENAI_API_KEY=sk-your-key-here

# Restart server
```

### "Embeddings generating but searches still slow"

**Cause**: IVFFLAT index needs tuning

**Fix** (production only):
```sql
-- In PostgreSQL
REINDEX INDEX index_lists_on_embedding;
REINDEX INDEX index_list_items_on_embedding;
```

### "Cross-org data appearing in search"

**Cause**: This shouldn't happen! Check `SearchService.accessible?`

**Fix**:
```ruby
# Report this as a bug - organization boundaries should be enforced
# All results are checked with accessible?()
# which verifies user's org membership
```

---

## Next Steps 🚀

### After Getting Search Working:
1. ✅ Test search manually
2. ✅ Verify embeddings are generating (check database)
3. ⬜ Integrate RAG into chat (if using chat)
4. ⬜ Add source attribution UI to chat (if using RAG)
5. ⬜ Monitor costs and performance
6. ⬜ Consider adding search to main navigation

### Advanced (Later):
- [ ] Add search analytics dashboard
- [ ] Cache frequent searches
- [ ] Bulk regenerate stale embeddings
- [ ] Add RAG toggle per chat
- [ ] Customize RAG prompts

---

## Documentation Map 📖

- **Quick Start**: `QUICK_START_RAG_SEARCH.md` ← Start here!
- **This Checklist**: `GETTING_STARTED_CHECKLIST.md` (you are here)
- **API Reference**: `API_ENDPOINTS_RAG_SEARCH.md`
- **Full Architecture**: `IMPLEMENTATION_PLAN.md`
- **Implementation Status**: `RAG_SEARCH_IMPLEMENTATION_STATUS.md`

---

## Support 🆘

If something isn't working:

1. **Check the logs**:
   ```bash
   tail -f log/development.log | grep -i "search\|embedding\|rag"
   ```

2. **Check the database**:
   ```ruby
   # In Rails console
   List.first.attributes  # See if embedding column exists
   ```

3. **Check the code**:
   - `app/services/search_service.rb` - Search logic
   - `app/services/rag_service.rb` - RAG logic
   - `app/services/embedding_generation_service.rb` - Embedding logic

4. **Manual test**:
   ```ruby
   # Test each component in isolation

   # Test embedding API
   response = RubyLLM::Embeddings.create(model: "text-embedding-3-small", input: "test")
   puts response.success?  # Should be true

   # Test search
   SearchService.call(query: "test", user: User.first)

   # Test RAG
   RagService.call(query: "test", user: User.first)
   ```

---

## Success Indicators ✨

You're done when:
- ✅ Migrations run without errors
- ✅ You can search and get results
- ✅ Results are from your lists/items
- ✅ Search respects org boundaries (you don't see other orgs' lists)
- ✅ Embeddings are generated automatically (check database)
- ✅ (Optional) RAG works in chat and shows sources

---

## Estimated Time

| Task | Time |
|------|------|
| Database setup | 30 sec |
| Test search | 5 min |
| RAG integration | 15 min |
| **Total** | **~20 min** |

---

## Celebrate! 🎉

Once you've completed this checklist, you have:
- ✨ Semantic search across your entire app
- 🤖 Always-on RAG for smarter chat
- 📚 Hybrid search (vector + keyword)
- 🔒 Secure org-scoped results
- 💰 Cost-effective ($0.07/month for 100 users)

**You're now ready for production!**

---

**Questions?** Check the docstrings in the code - they're detailed!

**Next?** Read `IMPLEMENTATION_PLAN.md` for deep architectural knowledge.
