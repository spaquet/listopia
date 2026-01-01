# Chat Architecture Refinement Proposal

## Executive Summary

Your current chat architecture has solid fundamentals (core logic, LLM integration, error handling are excellent). This proposal consolidates dual chat implementations into a **single, unified chat system** with:

1. **One Chat Model** - serving all contexts (dashboard, floating, inline)
2. **Context-Aware Rendering** - identical logic, context-aware presentation
3. **ChatGPT/Claude-like UI** - professional, modern design optimized for AI conversations
4. **Enhanced Search & Discovery** - "/" for commands, "@" for mentions, "#" for resources
5. **File Upload Support** - document and image attachments
6. **Chat History & Management** - browsing, organizing, searching past conversations
7. **Intelligent Context Injection** - app location awareness for smarter suggestions

---

## Part 1: Current State Analysis

### What's Working Well ✓
- Robust RubyLLM integration (v1.8+)
- Excellent error handling (retry logic, connection management)
- Good RAG foundation (metadata, sources attribution)
- Organization/team scoping architecture
- Core message processing (AiAgentMcpService)
- PostgreSQL foundation with vector support ready

### Pain Points to Address ✗
- **Two chat implementations** - dashboard vs floating (code duplication, inconsistent rendering)
- **Inconsistent context passing** - different data structures between chats
- **Not optimized for AI chat** - current UI designed for list/item collaboration, not AI conversations
- **Limited discovery** - no "/" commands, "@" mentions, "#" hashtags for smart search
- **File handling** - attachments exist in schema but minimal UI/UX
- **Chat history UX** - navigation and organization unclear
- **Missing conversation features** - no proper chat listing, no easy switching
- **Context awareness incomplete** - tells LLM where user is, but doesn't leverage it for smart features

---

## Part 2: Unified Chat Architecture

### 2.1 Single Chat Model (No Changes Needed)

Your `Chat` model already supports:
- ✓ User ownership with org/team scoping
- ✓ RAG toggle via metadata
- ✓ Title and status tracking
- ✓ Context storage (JSON)
- ✓ Conversation state tracking

**Recommendation**: Keep as-is. The model is well-designed.

### 2.2 Message Model (Minor Enhancements)

Current schema is excellent. Add support for:

```ruby
# app/models/message.rb enhancements

# 1. Message type tracking (for better rendering)
enum :message_subtype, { text: 0, command_result: 1, file_upload: 2, search_result: 3 }, prefix: true

# 2. File attachments (already available, just enhance UI)
has_many_attached :files

# 3. Reference metadata for mentions and commands
# Already in metadata JSON - just formalize structure:
# metadata: {
#   mentions: [{ type: "user|list|item", id: uuid, name: string }],
#   command: { name: string, args: {}, result: any },
#   search: { query: string, results_count: int }
# }
```

### 2.3 Single Unified Rendering Strategy

**Current Problem:**
- `_persistent_chat.html.erb` (floating) + `_embedded_chat.html.erb` (dashboard) = code duplication
- Slight differences in styling, behavior, key handling

**Solution: Context-Based Rendering with Partials**

```erb
<!-- app/views/chats/_unified_chat.html.erb -->

<!-- Single partial that adapts based on @chat_context -->
<div
  class="<%= @chat_context.css_classes %>"
  data-controller="unified-chat"
  data-unified-chat-mode-value="<%= @chat_context.mode %>" <!-- "floating" | "dashboard" | "inline" -->
  data-unified-chat-context-value="<%= @chat_context.to_json %>"
>
  <!-- Header: Different for each context -->
  <%= render "shared/chat_header", context: @chat_context %>

  <!-- Messages Container: Identical logic, styled by context -->
  <div class="<%= @chat_context.messages_container_classes %>">
    <%= render "shared/chat_messages", messages: @chat.messages %>
  </div>

  <!-- Input Area: Identical logic, styled by context -->
  <%= render "shared/chat_input", context: @chat_context %>
</div>
```

**Benefits:**
- Single rendering path
- DRY principle (no duplication)
- Easy to add new contexts (inline, sidebar, etc.)
- Consistent behavior everywhere

---

## Part 3: ChatGPT/Claude-like UI Design

### 3.1 Overall Layout Strategy

**Desktop:**
```
┌─────────────────────────────────────────────────────────────┐
│ Listopia Header (nav, user, org selector)                    │
├─────────────┬───────────────────────────────────────────────┤
│             │                                                │
│  Sidebar    │  Main Content Area                            │
│  (Chats)    │  (Dashboard, Lists, Items, etc.)             │
│             │                                                │
│             │  ┌─────────────────────────────────────────┐  │
│             │  │ Floating Chat (if not on dashboard)    │  │
│             │  │ - Minimizable                          │  │
│             │  │ - 384px wide (fixed)                   │  │
│             │  └─────────────────────────────────────────┘  │
└─────────────┴───────────────────────────────────────────────┘
```

**On Dashboard:**
```
┌──────────────────────────────────────────────────────────────┐
│ Listopia Header                                               │
├──────────────────────────────────────────────────────────────┤
│                                                               │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │                   Chat (Full Width)                    │ │
│ │                   - Shows chat history                │ │
│ │                   - Integrated input                  │ │
│ └─────────────────────────────────────────────────────────┘ │
│                                                               │
│ ┌─────────────────────────────────────────────────────────┐ │
│ │                   Lists Grid                          │ │
│ │                                                       │ │
│ └─────────────────────────────────────────────────────────┘ │
└──────────────────────────────────────────────────────────────┘
```

### 3.2 Professional Chat UI Components

#### A. Chat Sidebar (New)

```
┌─────────────────┐
│ 🔄 New Chat     │  ← Always visible button
├─────────────────┤
│ Search chats... │
├─────────────────┤
│ 📌 Recent       │
│ ├─ UI Design    │
│ ├─ API Bugs     │
│ └─ Q4 Planning  │
├─────────────────┤
│ 📂 All Chats    │
│ ├─ Folders      │
│ └─ ⋯            │
└─────────────────┘
```

**Features:**
- **"New Chat" button** - Prominent, always accessible
  - Creates new Chat record
  - Loads with empty state + suggestions based on context
  - Auto-focuses input for immediate typing
  - Shows welcome message with available commands
- Quick access to recent conversations
- Search within chat history
- Chat organization (optional folders/tags)
- Dark mode indicator

**"New Chat" Button Behavior:**

```erb
<!-- Button placement options: -->

<!-- 1. In chat sidebar (for multi-chat layout) -->
<div class="chat-sidebar">
  <%= button_to "🔄 New Chat", chats_path, method: :post,
      class: "w-full btn btn-primary mb-4",
      data: { turbo_method: :post, turbo_action: :replace } %>
  <!-- ... rest of sidebar -->
</div>

<!-- 2. In chat header (when viewing single chat) -->
<div class="chat-header">
  <h2>Chat History</h2>
  <%= button_to "New Chat", chats_path, method: :post,
      class: "btn btn-sm btn-outline",
      data: { turbo_method: :post } %>
</div>

<!-- 3. Floating button (on pages without dedicated chat area) -->
<div class="fixed bottom-6 right-6 z-40">
  <%= button_to new_chat_path, method: :post,
      class: "btn btn-circle btn-lg btn-primary shadow-lg" do %>
    <svg class="w-6 h-6" fill="none" stroke="currentColor" viewBox="0 0 24 24">
      <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 4v16m8-8H4"></path>
    </svg>
  <% end %>
</div>
```

**After "New Chat" Creation:**

```ruby
# app/controllers/chats_controller.rb
def create
  @chat = current_user.chats.create!(organization: current_organization)
  @chat_context = build_chat_context(@chat)

  respond_to do |format|
    format.turbo_stream do
      render turbo_stream: turbo_stream.replace("unified-chat",
        partial: "chat/unified_chat",
        locals: { chat: @chat, context: @chat_context, message_history: [] })
    end
    format.html { redirect_to chat_path(@chat) }
  end
end
```

**Empty State + Suggestions:**

```erb
<!-- app/views/chat/_empty_state.html.erb -->
<div class="flex flex-col items-center justify-center h-full gap-4 p-6 text-center">
  <div class="text-4xl">💬</div>
  <h2 class="text-lg font-semibold">Start a New Conversation</h2>
  <p class="text-gray-600 text-sm">
    Try asking me to help with your lists, search for content, or get started with commands.
  </p>

  <!-- Context-aware suggestions -->
  <div class="mt-4 space-y-2 w-full">
    <p class="text-xs text-gray-500 font-semibold">AVAILABLE COMMANDS:</p>
    <div class="grid gap-2">
      <button class="text-left px-3 py-2 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-800 text-sm">
        <span class="font-mono text-blue-600">/search</span> - Find your lists
      </button>
      <button class="text-left px-3 py-2 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-800 text-sm">
        <span class="font-mono text-blue-600">/browse</span> - Browse available lists
      </button>
      <button class="text-left px-3 py-2 rounded-lg hover:bg-gray-100 dark:hover:bg-gray-800 text-sm">
        <span class="font-mono text-blue-600">/help</span> - See all commands
      </button>
    </div>

    <!-- Context-specific suggestions -->
    <% if @focused_resource.present? %>
      <p class="text-xs text-gray-500 font-semibold mt-4">CONTEXT:</p>
      <div class="bg-blue-50 dark:bg-blue-900/20 rounded-lg p-3 text-sm">
        <p class="text-gray-600 dark:text-gray-300">
          Currently viewing <strong><%= @focused_resource.title %></strong>
        </p>
        <p class="text-xs text-gray-500 mt-1">Chat will include this in context for smarter responses</p>
      </div>
    <% end %>
  </div>
</div>
```

#### B. Message Container (ChatGPT-style)

```
┌──────────────────────────────────────────┐
│                                          │
│  User Message (right-aligned, colored)   │
│                                          │
│  ┌────────────────────────────────────┐ │
│  │ Assistant Message (left-aligned)   │ │
│  │ - Clean markdown rendering         │ │
│  │ - Code blocks with syntax highlight│ │
│  │ - Copy buttons on code             │ │
│  │ - RAG sources inline               │ │
│  │                                    │ │
│  │ [Source: List name] [Link]         │ │
│  └────────────────────────────────────┘ │
│                                          │
│  User message again...                   │
│                                          │
└──────────────────────────────────────────┘
```

**Key Styling:**
- User messages: Right-aligned, accent color background, white text
- Assistant messages: Left-aligned, subtle background (light gray/dark theme variant)
- Messages bubble style with proper spacing
- Clear visual hierarchy

#### C. Input Area (Enhanced)

```
┌──────────────────────────────────────────────────────┐
│ @                      #            /               │
│ (mentions)             (resources)  (commands)       │
├──────────────────────────────────────────────────────┤
│ [📎] Type your message...              [⚙] [Send]   │
│      Max 4000 chars                                  │
├──────────────────────────────────────────────────────┤
│ 📎 Attach files                                      │
│ / Search (lists, items, people)                     │
│ @ Mention people or resources                       │
│ # Find lists, items, tags                           │
└──────────────────────────────────────────────────────┘
```

**Features:**
- Rich text input with auto-complete
- "/" commands (see below)
- "@" mentions
- "#" hashtag search
- File attachment button with preview
- Character counter
- Command palette

---

## Part 4: Smart Search & Navigation Features

### 4.1 Search: Explicit Commands vs. Automatic Detection

**Decision: Use Explicit "/" Commands Only**

You asked: *"Should search be automatically detected or use explicit `/search` command?"*

**Recommendation:** Explicit `/search` command. Here's why:

**Problems with Auto-Detection:**

```
User: "Can you find my budget list?"
System: ??? Search or answer as AI?

User: "Who works on the marketing project?"
System: ??? Search for user or ask LLM?

User: "Show me recent lists"
System: ??? Is this a search or a question?
```

Auto-detection requires NLP to disambiguate → harder to predict, more AI calls, confusing behavior.

**Benefits of Explicit `/search`:**

- ✅ **Clarity** - User controls exactly what happens
- ✅ **Predictable** - Same input always gives same output
- ✅ **Powerful** - Can add advanced options: `/search budget --in:finance --sort:recent`
- ✅ **Discoverability** - Users learn one pattern for searching
- ✅ **Efficient** - No wasted AI calls on disambiguation
- ✅ **Mobile-Friendly** - Command palette easier than phrasing perfect questions

**UX Pattern:**

```
User sees:
"Try /search to find lists, /browse to see all, or /help for more"

User types: "/search budget"
System: Shows command palette with hint
System: Executes search, displays results as formatted template
```

**The Balance:**

You still want smart natural conversation for questions:

```
✅ Good: "What's the status of our Q4 planning?"
   → LLM answers conversationally with RAG context

✅ Good: "/search Q4 planning"
   → Get direct search results

✅ Good: "Tell me about @john_smith"
   → LLM provides info about user

✅ Bad: "Find me Q4 planning"
   → Ambiguous without explicit /search
```

### 4.2 "/" Command System

```ruby
# app/models/chat_command.rb (new)
COMMANDS = {
  "/help" => "Show available commands",
  "/search <query>" => "Search lists, items, comments (RAG if enabled)",
  "/browse [filter]" => "Browse your lists with optional filter",
  "/settings" => "Chat settings (RAG toggle, model, etc.)",
  "/export" => "Export this conversation",
  "/new" => "Start a new chat",
  "/clear" => "Clear current chat history",
  "/history" => "Browse past conversations",
  "/teams" => "Show team members",
  "/lists [filter]" => "Show lists in current context",
  "/recent" => "Show recent activity",
  "/info <resource>" => "Get detailed info on resource"
}
```

**Implementation:**

```javascript
// Trigger on "/" input
// Show command palette with descriptions
// Provide parameter hints for commands that take args
// Execute command server-side (e.g., /search → SearchService)
// Return structured response via Turbo Stream
```

### 4.2 "@" Mention System (Future Enhancement)

Keep design simple for now - mentions are for reference/context:

```
User types: "Can you help me with @"

Autocomplete shows:
- Users in current org/team
- Teams (optional)

Selected: @john_smith
→ Stored in message metadata with context
→ In future: Could trigger notifications
→ For now: Just reference tracking
```

**Data Structure:**
```json
{
  "mentions": [
    {
      "type": "user",
      "id": "uuid",
      "name": "John Smith",
      "organization_id": "uuid"
    }
  ]
}
```

### 4.3 "#" Resource Search (Future Enhancement)

**Recommendation:** Start without "#" in Phase 1. Use `/search` instead.

**Later Enhancement:** When needed, implement as:
```
/search #project-roadmap
→ Search within that list
→ Scopes results to list context

# Alternative (future):
"Tell me about #product-roadmap"
→ Triggers /search #product-roadmap automatically
```

Use explicit `/search` first, add "#" shorthand when user feedback demands it.

---

## Part 5: Message Templates System

### 5.1 Template-Based Rendering

Your dashboard already uses templates to render specific message types (lists created, items, etc.). We should extend this to support:

**Purpose:** Render rich, formatted messages for different content types - not just plain text/markdown.

**Template Types:**

```ruby
# app/models/message_template.rb (new)
class MessageTemplate
  REGISTRY = {
    # User/Team/Org info
    "user_profile" => UserProfileTemplate,
    "team_summary" => TeamSummaryTemplate,
    "org_stats" => OrgStatsTemplate,

    # List/Item operations
    "list_created" => ListCreatedTemplate,
    "lists_created" => ListsCreatedTemplate,
    "items_created" => ItemsCreatedTemplate,
    "item_assigned" => ItemAssignedTemplate,

    # Search & discovery
    "search_results" => SearchResultsTemplate,
    "command_result" => CommandResultTemplate,

    # File uploads
    "file_uploaded" => FileUploadedTemplate,
    "files_processed" => FilesProcessedTemplate,

    # System messages
    "rag_sources" => RAGSourcesTemplate,
    "error" => ErrorTemplate,
    "success" => SuccessTemplate,
  }
end
```

**Template Structure:**

```erb
<!-- app/views/message_templates/_user_profile.html.erb -->
<div class="bg-gradient-to-r from-blue-50 to-indigo-50 rounded-lg p-4 border border-blue-200">
  <div class="flex items-center gap-3">
    <div class="w-12 h-12 bg-gradient-to-br from-blue-500 to-indigo-600 rounded-full flex items-center justify-center text-white font-bold">
      <%= user.name.first.upcase %>
    </div>
    <div class="flex-1">
      <h3 class="font-semibold text-gray-900"><%= user.name %></h3>
      <p class="text-sm text-gray-600"><%= user.email %></p>
    </div>
  </div>
  <div class="mt-3 pt-3 border-t border-blue-200 grid grid-cols-2 gap-2 text-sm">
    <div>
      <span class="text-gray-600">Lists:</span>
      <span class="font-semibold text-gray-900"><%= user.lists.count %></span>
    </div>
    <div>
      <span class="text-gray-600">Teams:</span>
      <span class="font-semibold text-gray-900"><%= user.teams.count %></span>
    </div>
  </div>
</div>
```

**Implementation in Message View:**

```erb
<!-- app/views/shared/_chat_message.html.erb (unified) -->
<div class="chat-message <%= message.role %>">
  <!-- Use template if message has template_type -->
  <% if message.template_type.present? %>
    <%= render "message_templates/#{message.template_type}", data: message.metadata["template_data"] %>
  <% else %>
    <!-- Fall back to markdown rendering for regular messages -->
    <div class="message-content">
      <%= render_markdown(message.content) %>
    </div>
  <% end %>

  <!-- Always show RAG sources if present -->
  <% if message.metadata["rag_sources"].present? %>
    <%= render "message_templates/rag_sources", sources: message.metadata["rag_sources"] %>
  <% end %>
</div>
```

**Database Enhancement:**

```ruby
# db/migrate/TIMESTAMP_add_template_support_to_messages.rb
class AddTemplateSupportToMessages < ActiveRecord::Migration[8.0]
  def change
    add_column :messages, :template_type, :string
    add_index :messages, :template_type
    # Store template data in metadata under "template_data" key
    # Example: metadata: { template_data: { user_id: "uuid", name: "John" } }
  end
end
```

### 5.2 Markdown Support in Chat

All message content should support **full markdown rendering** with:

```ruby
# app/helpers/markdown_helper.rb
def render_markdown(content)
  markdown = Markdown.new(
    content,
    hard_wrap: true,
    link_attributes: { target: "_blank", rel: "noopener noreferrer" }
  )

  sanitize(
    markdown.to_html,
    tags: %w[p br h1 h2 h3 h4 h5 h6 strong em u code pre ul ol li blockquote a img hr table thead tbody tr th td],
    attributes: { "a" => ["href", "target", "rel"], "img" => ["src", "alt"], "code" => ["class"] }
  )
end
```

**Markdown Features Supported:**

- ✓ **Basic formatting** - bold, italic, underline
- ✓ **Code blocks** - with syntax highlighting and copy button
- ✓ **Lists** - ordered, unordered, nested
- ✓ **Links** - auto-linkify, open in new tab
- ✓ **Images** - embedded display
- ✓ **Tables** - structured data display
- ✓ **Blockquotes** - quoted text
- ✓ **Code inline** - `code snippets`

**Example Message Content:**

```markdown
Here's a summary of the Q4 planning:

## Key Initiatives
1. **Design System** - Complete by Oct 15
2. **Performance** - <10s page load time
3. **Mobile** - Full responsive redesign

### Architecture
\`\`\`ruby
# New chat system
class UnifiedChat < ApplicationRecord
  has_many :messages
end
\`\`\`

**Sources:**
- [Architecture Doc](https://internal.example.com/docs)
- #product-roadmap list

---
```

---

## Part 6: Context-Aware Intelligence

### 5.1 Smart Context Injection

**Current:** Chat knows `{ page, user_id, org_id, total_lists }`

**Enhanced:** Context object includes:

```ruby
# app/models/chat_context.rb
{
  # Location in app
  page: "lists#show",
  current_list_id: "uuid",
  current_item_id: "uuid",
  current_team_id: "uuid",

  # User context
  user_id: "uuid",
  organization_id: "uuid",

  # Aggregated stats
  total_lists: 42,
  shared_lists: 5,
  team_members: 3,

  # Current resource snapshot
  focused_resource: {
    type: "list" | "item" | "team",
    id: "uuid",
    title: "string",
    summary: "string" # First 200 chars
  },

  # Smart suggestions
  recent_collaborations: [...],
  frequently_used_lists: [...],
  teams: [...],

  # Navigation breadcrumb
  breadcrumb: ["Org Name", "Team Name", "List Name"]
}
```

### 5.2 Smart Suggestions

Based on context, show relevant prompts:

```erb
<!-- When viewing a list -->
<div class="chat-suggestions">
  "Summarize this list"
  "Create items for:"
  "Assign items to:"
  "Find duplicates"
</div>

<!-- When on dashboard -->
<div class="chat-suggestions">
  "Create a new list"
  "Search my lists"
  "Summary of my lists"
  "Who's working on what?"
</div>

<!-- When in a team -->
<div class="chat-suggestions">
  "Team status"
  "Who's available?"
  "Team priorities"
  "Recent activity"
</div>
```

---

## Part 6: File Upload & Rich Media

### 6.1 File Attachment Flow

```
User clicks [📎] attachment button
→ Select files (images, PDFs, docs, CSVs)
→ Preview before sending
→ Attach to message
→ Send to LLM with content

LLM processes:
- Image: Vision analysis, OCR
- PDF: Extract text/structure
- CSV: Parse table structure
- Docs: Analyze content
```

### 6.2 Implementation

```ruby
# app/models/message.rb
has_many_attached :files

# app/services/file_processor_service.rb
# Extracts content from files
# Sends to LLM as context
# Stores processing results in metadata

metadata: {
  files: [
    {
      filename: "screenshot.png",
      size: 256000,
      mime_type: "image/png",
      processed: true,
      content_extracted: "text extracted from image",
      processing_time: 2.5
    }
  ]
}
```

---

## Part 7: Chat History & Discovery

### 7.1 Chat List View (New Route)

**Route:** `GET /chats` (or in sidebar)

**Features:**
- List all chats for current user/org
- Search within chat titles/messages
- Sort by: recent, oldest, starred, title
- Pagination (20 per page)
- Quick actions: delete, archive, export
- Bulk operations (select multiple)

```erb
<!-- app/views/chats/index.html.erb -->
<div class="chat-history">
  <div class="search-bar">
    <%= search_field_tag :q, params[:q], class: "search-input" %>
  </div>

  <div class="chat-list">
    <% @chats.each do |chat| %>
      <div class="chat-item">
        <h3><%= chat.title %></h3>
        <p class="preview"><%= chat.messages.last&.content.truncate(100) %></p>
        <p class="meta">
          <%= time_ago_in_words(chat.last_message_at) %>
          · <%= chat.messages.count %> messages
          · Org: <%= chat.organization.name %>
        </p>
        <div class="actions">
          <%= link_to "Open", chat_path(chat) %>
          <%= button_to "Delete", chat_path(chat), method: :delete %>
        </div>
      </div>
    <% end %>
  </div>
</div>
```

### 7.2 Chat Metadata Enhancements

Add to Chat model:

```ruby
# app/models/chat.rb additions
add_column :chats, :title_override, :string        # User-customized title
add_column :chats, :preview_message, :text         # Last message preview
add_column :chats, :is_starred, :boolean           # Quick access
add_column :chats, :tags, :jsonb                   # Custom tags
add_column :chats, :folder_id, :uuid               # Organization (optional)

scope :recent, -> { order(last_message_at: :desc) }
scope :starred, -> { where(is_starred: true) }
scope :search, ->(query) { where("title ILIKE ?", "%#{query}%") }
```

---

## Part 8: Implementation Roadmap

### Phase 1: Foundation (Week 1)
- [ ] Create unified chat context object
- [ ] Build `_unified_chat` base partial
- [ ] Consolidate Stimulus controller (single `unified-chat` controller)
- [ ] Update routing (remove duplicate routes if applicable)
- [ ] Verify both contexts (floating, dashboard) work with unified UI

**Outcome:** One rendering pipeline serving all contexts

### Phase 2: Modern UI (Week 1-2)
- [ ] Redesign message bubbles (ChatGPT style)
- [ ] Create chat sidebar component
- [ ] Implement context-aware suggestions
- [ ] Add proper markdown/code rendering with copy buttons
- [ ] Polish input area styling

**Outcome:** Professional AI chat interface

### Phase 3: Smart Features (Week 2)
- [ ] Implement "/" command system
- [ ] Add "@" mention autocomplete
- [ ] Add "#" resource search/hashtags
- [ ] Build command palette UI

**Outcome:** Power user features for discoverability

### Phase 4: File Uploads (Week 2-3)
- [ ] Create file upload UI component
- [ ] Implement file processor service
- [ ] Integrate with message metadata
- [ ] Test with different file types (images, PDFs, CSVs)

**Outcome:** Rich media support in chat

### Phase 5: Chat History (Week 3)
- [ ] Create ChatsController#index
- [ ] Build chat list view
- [ ] Implement chat search
- [ ] Add chat management (delete, archive, star)
- [ ] Add export functionality

**Outcome:** Easy chat discovery and management

### Phase 6: Polish & Testing (Week 3-4)
- [ ] Comprehensive testing (unit, integration, system)
- [ ] Performance optimization (pagination, lazy loading)
- [ ] Mobile responsiveness
- [ ] Accessibility audit (WCAG)
- [ ] Error handling for all new features

**Outcome:** Production-ready unified chat system

---

## Part 9: Technical Specifications

### 9.1 New Models

```ruby
# app/models/chat_context.rb
class ChatContext
  attr_accessor :mode, :user_id, :organization_id, :team_id, :focused_resource, :page, :breadcrumb

  def floating?; mode == "floating"; end
  def dashboard?; mode == "dashboard"; end
  def inline?; mode == "inline"; end

  def css_classes
    case mode
    when "floating"
      "fixed bottom-4 right-4 w-96 h-128 rounded-lg shadow-lg border border-gray-200"
    when "dashboard"
      "w-full h-96 rounded-lg border border-gray-200"
    when "inline"
      "w-full h-64 rounded-lg border border-gray-200"
    end
  end

  def messages_container_classes
    "flex-1 overflow-y-auto #{mode == 'floating' ? 'h-96' : 'h-full'}"
  end

  def to_json
    {
      mode: mode,
      user_id: user_id,
      organization_id: organization_id,
      page: page,
      focused_resource: focused_resource,
      breadcrumb: breadcrumb
    }.to_json
  end
end

# app/models/chat_command.rb
class ChatCommand
  REGISTRY = {
    "help" => { description: "Show available commands", handler: :handle_help },
    "search" => { description: "Search content", handler: :handle_search },
    "browse" => { description: "Browse lists", handler: :handle_browse },
    "export" => { description: "Export conversation", handler: :handle_export },
    "new" => { description: "Start new chat", handler: :handle_new },
  }

  def self.execute(command, args, user, chat)
    # Route to appropriate handler
  end
end
```

### 9.2 New Controllers

```ruby
# app/controllers/chats_controller.rb
class ChatsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_chat, only: [:show, :destroy, :star, :unstar]

  def index
    @chats = policy_scope(Chat).recent.page(params[:page])
  end

  def show
    authorize @chat
    @context = build_chat_context(@chat)
    respond_to do |format|
      format.html
      format.turbo_stream
    end
  end

  def destroy
    authorize @chat
    @chat.discard
    redirect_to chats_path, notice: "Chat deleted"
  end

  def star
    authorize @chat
    @chat.update(is_starred: true)
    render turbo_stream: turbo_stream.replace(@chat, @chat)
  end

  private

  def build_chat_context(chat)
    ChatContext.new(
      mode: params[:mode] || detect_mode,
      user_id: current_user.id,
      organization_id: current_organization.id,
      page: "#{controller_name}##{action_name}",
      breadcrumb: build_breadcrumb
    )
  end

  def detect_mode
    request.xhr? ? "floating" : "dashboard"
  end

  def build_breadcrumb
    # Build based on URL/context
  end
end

# app/controllers/chat/commands_controller.rb
module Chat
  class CommandsController < ApplicationController
    before_action :authenticate_user!

    def execute
      command_name = params[:command]
      command_class = ChatCommand.for(command_name)

      result = command_class.execute(
        args: params[:args],
        user: current_user,
        chat: @chat
      )

      respond_to do |format|
        format.turbo_stream { render_command_result(result) }
      end
    end
  end
end
```

### 9.3 Database Migrations

```ruby
# db/migrate/TIMESTAMP_enhance_chats_for_unified_ui.rb
class EnhanceChatsForUnifiedUi < ActiveRecord::Migration[8.0]
  def change
    # Chat enhancements
    add_column :chats, :title_override, :string
    add_column :chats, :preview_message, :text
    add_column :chats, :is_starred, :boolean, default: false
    add_column :chats, :tags, :jsonb
    add_column :chats, :folder_id, :uuid

    # Message enhancements
    add_column :messages, :message_subtype, :integer, default: 0
    add_index :messages, [:chat_id, :message_subtype]
    add_index :messages, [:chat_id, :created_at]

    # Indexing for search/sort
    add_index :chats, [:user_id, :last_message_at]
    add_index :chats, [:user_id, :is_starred]
  end
end
```

### 9.4 New Stimulus Controller

```javascript
// app/javascript/controllers/unified_chat_controller.js

import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "messagesContainer", "messageInput", "sendButton",
    "suggestionsBar", "typingIndicator", "fileInput"
  ]

  static values = {
    userId: String,
    mode: String, // floating, dashboard, inline
    context: Object,
    chatId: String
  }

  connect() {
    this.setupMessageContainer()
    this.setupInputHandling()
    this.loadChatHistory()
    this.setupAutoComplete()
  }

  // Message handling
  sendMessage(event) {
    if (!this.messageInputTarget.value.trim()) return

    const message = this.messageInputTarget.value
    const files = this.getAttachedFiles()

    this.createFormData(message, files)
      .then(formData => this.submitMessage(formData))
  }

  // File handling
  attachFile(event) {
    const files = event.currentTarget.files
    this.previewFiles(files)
    this.fileInputTarget.dataset.attached = true
  }

  // Command palette
  handleCommandPalette(event) {
    if (event.key === "/" && !this.hasSelection()) {
      this.showCommandPalette()
    }
  }

  // Mention autocomplete
  handleMentions(event) {
    if (event.key === "@") {
      this.showMentionAutocomplete()
    }
  }

  // Resource search
  handleResourceSearch(event) {
    if (event.key === "#") {
      this.showResourceSearch()
    }
  }

  // Rest of implementation...
}
```

---

## Part 10: Design System Updates

### 10.1 Chat-Specific Tailwind Classes

```scss
// app/assets/stylesheets/chat.scss

// Message styling
.chat-message {
  @apply flex mb-4 gap-3;

  &.user {
    @apply flex-row-reverse;

    .message-bubble {
      @apply bg-blue-500 text-white rounded-lg rounded-tr-none;
    }
  }

  &.assistant {
    .message-bubble {
      @apply bg-gray-100 dark:bg-gray-800 text-gray-900 dark:text-gray-100 rounded-lg rounded-tl-none;
    }
  }
}

.message-bubble {
  @apply px-4 py-2 max-w-xs lg:max-w-md xl:max-w-lg;

  code {
    @apply bg-gray-900 text-gray-100 px-2 py-1 rounded font-mono text-sm;
  }
}

// Input styling
.chat-input {
  @apply border-t border-gray-200 dark:border-gray-700 p-4;
}

.input-wrapper {
  @apply flex gap-2 items-end;
}

.message-textarea {
  @apply flex-1 resize-none focus:outline-none border border-gray-300 rounded-lg px-3 py-2;
  max-height: 200px;
  min-height: 44px;
}

// Suggestions
.chat-suggestions {
  @apply flex gap-2 flex-wrap mb-4;

  .suggestion {
    @apply px-3 py-2 bg-gray-100 hover:bg-gray-200 rounded-lg cursor-pointer text-sm;
  }
}

// Sidebar
.chat-sidebar {
  @apply w-64 bg-white dark:bg-gray-900 border-r border-gray-200 dark:border-gray-800 flex flex-col;
}
```

---

## Part 11: Security & Authorization

### 11.1 Chat Access Control

```ruby
# app/policies/chat_policy.rb
class ChatPolicy < ApplicationPolicy
  def index?
    user.present?
  end

  def show?
    # User must be in chat's organization
    record.user_id == user.id ||
    user.in_organization?(record.organization)
  end

  def create?
    user.present?
  end

  def destroy?
    record.user_id == user.id || user.admin_in_organization?(record.organization)
  end
end
```

### 11.2 Command Execution Safety

```ruby
# app/services/chat_command_service.rb
class ChatCommandService
  ALLOWED_COMMANDS = [
    "help", "search", "browse", "settings",
    "export", "new", "clear", "history"
  ]

  def initialize(command, args, user, chat)
    @command = command
    @args = args
    @user = user
    @chat = chat
  end

  def execute
    raise "Unauthorized command" unless allowed?

    case @command
    when "search"
      SearchService.call(query: @args[:q], user: @user)
    when "browse"
      @user.accessible_lists.limit(10)
    # ... other commands
    end
  end

  private

  def allowed?
    ALLOWED_COMMANDS.include?(@command)
  end
end
```

---

## Part 12: Performance Considerations

### 12.1 Optimization Strategies

1. **Message Loading**
   - Load latest 50 messages initially
   - Infinite scroll loads older messages
   - Index on `[chat_id, created_at]`

2. **Chat History**
   - Paginate list view (20 per page)
   - Lazy-load previews
   - Cache recent chats (5 min)

3. **Context Building**
   - Cache context object (2 min)
   - Pre-compute aggregated stats in background job
   - Use database views for complex queries

4. **File Processing**
   - Background job for file extraction
   - Stream large files (chunked upload)
   - Cache processed content

### 12.2 Caching Strategy

```ruby
# Solid Cache integrations
Rails.cache.fetch("chat:#{chat.id}:context", expires_in: 2.minutes) do
  build_chat_context(chat)
end

Rails.cache.fetch("user:#{user.id}:accessible_lists", expires_in: 5.minutes) do
  user.accessible_lists
end

Rails.cache.fetch("search:#{query_hash}", expires_in: 15.minutes) do
  SearchService.call(query: query, user: user)
end
```

---

## Part 13: Testing Strategy

### 13.1 Test Coverage

```ruby
# spec/models/chat_spec.rb
describe Chat do
  it "maintains association with user and organization"
  it "scopes chats by organization"
  it "tracks last message timestamp"
  it "supports RAG toggle"
end

# spec/controllers/chats_controller_spec.rb
describe ChatsController do
  it "lists only user's chats"
  it "prevents access to other users' chats"
  it "respects organization boundaries"
  it "supports search filtering"
  it "supports pagination"
end

# spec/services/chat_command_service_spec.rb
describe ChatCommandService do
  it "executes allowed commands"
  it "rejects unauthorized commands"
  it "validates command arguments"
  it "returns structured results"
end

# spec/javascript/controllers/unified_chat_controller_spec.js
describe("UnifiedChatController", () => {
  it("sends messages via Turbo")
  it("handles file attachments")
  it("shows command palette on /")
  it("shows mentions on @")
  it("shows resources on #")
  it("maintains scroll position")
})

# spec/system/chat_system_spec.rb
feature "Chat System" do
  scenario "User can create and view chat"
  scenario "User can send message and see response"
  scenario "User can upload file and chat"
  scenario "User can use commands"
  scenario "User can search chat history"
end
```

---

## Part 14: Migration Plan

### 14.1 Backward Compatibility

```ruby
# During transition, support both old and new UI
class ApplicationController < ActionController::Base
  helper_method :use_new_chat_ui?

  def use_new_chat_ui?
    current_user&.feature_flags&.[]("new_chat_ui") ||
    Rails.env.development?
  end
end

# In views:
<% if use_new_chat_ui? %>
  <%= render "chat/unified_chat" %>
<% else %>
  <%= render "chat/persistent_chat" %>
<% end %>
```

### 14.2 Data Migration

```ruby
# No data migration needed - all existing chats and messages
# remain valid. New fields have defaults.
#
# Migration steps:
# 1. Deploy with both UIs active (feature flag)
# 2. Collect feedback
# 3. Gradually enable new UI (% of users)
# 4. Monitor performance
# 5. Deprecate old UI
# 6. Remove old code (4-6 weeks after full rollout)
```

---

## Part 15: Implementation Checklist

### Before Starting

- [ ] Review and approve this architecture
- [ ] Confirm explicit `/search` approach (no auto-detection)
- [ ] Review template system design and extend as needed
- [ ] Decide on chat folders/organization (or keep flat)
- [ ] Determine file size limits
- [ ] Plan mobile experience

### Phase 1: Foundation

- [ ] Create ChatContext class
- [ ] Create _unified_chat partial (dashboard + floating contexts)
- [ ] Create unified-chat Stimulus controller
- [ ] Update routing to serve both contexts from single partial
- [ ] Test floating context works
- [ ] Test dashboard context works
- [ ] Verify message rendering consistency

### Phase 2: Markdown & Templates

- [ ] Add markdown helper with full syntax support
- [ ] Create message template system (MessageTemplate registry)
- [ ] Create base templates: user_profile, lists_created, items_created, search_results
- [ ] Add `template_type` column to messages
- [ ] Implement unified message rendering with template fallback
- [ ] Create database migration for template_type column
- [ ] Test template rendering for all types

### Phase 3: "New Chat" Button & Empty State

- [ ] Add "New Chat" button to UI (3 placement options)
- [ ] Create ChatsController#create action
- [ ] Implement empty state with command suggestions
- [ ] Context-aware suggestions based on focused resource
- [ ] Auto-focus input after creating new chat
- [ ] Test button placement in different contexts

### Phase 4: Commands System (Phase 1: `/search` only)

- [ ] Create ChatCommand model with registry
- [ ] Implement "/" command detection in Stimulus controller
- [ ] Create command palette UI with parameter hints
- [ ] Implement `/search` command handler
- [ ] Implement `/help` command
- [ ] Return command results as formatted templates
- [ ] Test command execution and result rendering

### Phase 5: File Uploads

- [ ] Create file upload component with preview
- [ ] File processor service (images, PDFs, CSVs, docs)
- [ ] Integration with message metadata
- [ ] File attachment UI in messages
- [ ] Integration tests for different file types

### Phase 6: Chat History & Management

- [ ] Create ChatsController#index (list all chats)
- [ ] Create chat list view with search
- [ ] Implement pagination (20 per page)
- [ ] Add delete/star/archive operations
- [ ] Add export functionality
- [ ] Search within chat messages

### Phase 7: Additional Commands (Future)

- [ ] Implement `/browse`, `/lists`, `/teams` commands
- [ ] Implement `/settings` for RAG toggle
- [ ] Implement `/history` for chat listing
- [ ] Implement `/info` for resource details

### Phase 8: Polish & Optimization

- [ ] Performance testing (message load, search)
- [ ] Mobile responsiveness (buttons, input, sidebar)
- [ ] Accessibility audit (WCAG)
- [ ] Error handling for all features
- [ ] Comprehensive system tests
- [ ] Monitor and optimize N+1 queries

---

## Part 16: Success Metrics

After implementation, these should improve:

| Metric | Current | Target | Measurement |
|--------|---------|--------|-------------|
| Chat UI Consistency | ~60% | 100% | Code duplication checks |
| Time to New Chat | ~2s | <1s | Performance monitoring |
| Message Load Time | ~1.5s | <500ms | RUM metrics |
| Users Using Commands | 0% | >30% | Analytics |
| File Upload Usage | ~10% | >40% | Feature analytics |
| Chat History Discovery | Limited | Easy | User surveys |
| Mobile Experience | Awkward | Excellent | Responsive design tests |

---

## Part 17: Security, Moderation & Content Rating

### 17.1 Content Moderation (OpenAI API)

**Status:** Already implemented and working ✅

Your system already uses **RubyLLM's moderation API** (powered by OpenAI's moderation model):

```ruby
# Location: app/services/ai_agent_mcp_service.rb (lines 262-305)
# Status: Active in production via LISTOPIA_USE_MODERATION=true

# Blocks content in categories:
- hate (and hate/threatening)
- violence (and violence/graphic)
- self-harm (and intentional/instructions)
- sexual (and sexual/minors)

# Configuration:
config/initializers/ruby_llm_moderation.rb
- Model: OPENAI_MODERATION_MODEL (defaults to omni-moderation-latest)
- Enabled by default, logs all moderation decisions
```

**Cost Implications:**
- ✅ OpenAI moderation API is **included free** with API credits
- Uses minimal tokens (~100 chars = minimal cost)
- Runs on every message before processing
- No additional charge beyond standard OpenAI API costs

**Enhancement Recommendation:**
```ruby
# Add more detailed logging for moderation decisions
def moderate_content(content)
  result = RubyLLM.moderate(content: content, model: ENV['OPENAI_MODERATION_MODEL'])

  # NEW: Log moderation metadata
  metadata = {
    moderation_id: result.id,
    categories_flagged: result.categories,
    severity_scores: result.category_scores,
    checked_at: Time.current,
    user_id: @user.id,
    organization_id: @organization.id
  }

  # Log for audit trail
  Rails.logger.warn("Content moderated", metadata)

  # NEW: Store moderation result for dashboard monitoring
  ModerationLog.create!(
    user_id: @user.id,
    flagged: result.flagged,
    categories: result.categories,
    metadata: metadata
  )

  return { success: !result.flagged, result: result, metadata: metadata }
end
```

---

### 17.2 Prompt Injection & Jailbreak Detection

**Status:** Currently missing - HIGH PRIORITY ⚠️

Your system does NOT currently protect against:
1. Direct prompt injection attacks
2. Jailbreak attempts (role-playing, system prompt leakage)
3. Adversarial prompts targeting specific vulnerabilities
4. Context hijacking in multi-turn conversations

**Implementation Strategy:**

```ruby
# app/services/prompt_injection_detector.rb (new)
class PromptInjectionDetector
  # Common jailbreak patterns to detect
  JAILBREAK_PATTERNS = [
    /ignore[d]? (previous|earlier|above) (instructions|rules|guidelines|prompts?)/i,
    /pretend[ing]? (to be|you are|you're) (?!yourself)/i,
    /act[ing]? as (?!listopia|assistant)/i,
    /switch[ing]? (roles?|modes?|to administrator)/i,
    /show[ing]? (the system prompt|your instructions|your rules)/i,
    /what[']?s (your system prompt|the secret password)/i,
    /debug[ging]?.*mode/i,
    /(jailbreak|exploit|vulnerability|bypass|circumvent) (the|this|rules?|restrictions?)/i,
    /\b(role play|roleplaying|pretend|assume a role)\b/i,
    /simulate[d]? (a|an) (developer|admin|unauthorized user)/i,
  ]

  # Suspicious patterns that may indicate misuse
  SUSPICIOUS_PATTERNS = [
    /^\s*(test|exploit|vulnerability|security|hacker)/i,
    /(prompt injection|jailbreak|adversarial|red team)/i,
    /request unlimited|give me all|access everything/i,
    /(disable|bypass|remove|ignore) (safety|restrictions|controls|checks)/i,
  ]

  # Injection markers
  INJECTION_MARKERS = [
    "---",      # Prompt boundary marker
    ">>>",      # Prompt separator
    "==",       # Section divider
    "</prompt>", # XML tag
    "[/INST]",  # LLaMA format
  ]

  def initialize(message, user, chat_context)
    @message = message
    @user = user
    @chat_context = chat_context
  end

  def analyze
    {
      is_jailbreak_attempt: detect_jailbreak,
      is_suspicious: detect_suspicious_intent,
      has_injection_markers: detect_injection_markers,
      risk_level: calculate_risk_level,
      detected_patterns: @detected_patterns
    }
  end

  private

  def detect_jailbreak
    JAILBREAK_PATTERNS.any? do |pattern|
      if @message.match?(pattern)
        @detected_patterns ||= []
        @detected_patterns << pattern.source
        true
      end
    end
  end

  def detect_suspicious_intent
    SUSPICIOUS_PATTERNS.any? do |pattern|
      @message.match?(pattern)
    end
  end

  def detect_injection_markers
    INJECTION_MARKERS.any? { |marker| @message.include?(marker) }
  end

  def calculate_risk_level
    detection_count = [
      detect_jailbreak,
      detect_suspicious_intent,
      detect_injection_markers
    ].count(true)

    case detection_count
    when 2.. then "high"
    when 1   then "medium"
    else          "low"
    end
  end
end
```

**Integration in AiAgentMcpService:**

```ruby
# app/services/ai_agent_mcp_service.rb (enhancement)

def process_message
  # 1. Check moderation (existing)
  moderation_result = moderate_content(@current_message)
  return moderation_result if !moderation_result[:success]

  # 2. NEW: Check for prompt injection
  injection_detector = PromptInjectionDetector.new(
    @current_message,
    @user,
    @chat_context
  )
  injection_analysis = injection_detector.analyze

  # Log suspicious activity
  log_security_event(injection_analysis)

  # Handle based on risk level
  case injection_analysis[:risk_level]
  when "high"
    # Block and alert
    return {
      success: false,
      error: "Message appears to contain instructions to bypass safety guidelines. Please rephrase your request.",
      error_type: "prompt_injection_detected"
    }
  when "medium"
    # Log and proceed with caution
    Rails.logger.warn("Suspicious prompt detected", injection_analysis)
  when "low"
    # Proceed normally
  end

  # 3. Continue with normal processing
  # ... rest of the flow
end

private

def log_security_event(analysis)
  SecurityLog.create!(
    user_id: @user.id,
    event_type: "prompt_analysis",
    risk_level: analysis[:risk_level],
    detected_patterns: analysis[:detected_patterns],
    message_id: @chat.messages.last&.id,
    metadata: analysis
  )
end
```

---

### 17.3 Access Control & Data Leakage Prevention

**Status:** Strong - Pundit + Rolify in place ✅

Your system properly enforces:
- Organization boundaries via `policy_scope`
- Role-based permissions
- Search result filtering
- RAG context isolation

**Enhancement: Add Authorization Audit**

```ruby
# app/models/security_audit.rb (new)
class SecurityAudit < ApplicationRecord
  enum event_type: {
    authorization_granted: 0,
    authorization_denied: 1,
    data_accessed: 2,
    search_performed: 3,
    prompt_injection_detected: 4,
    moderation_flagged: 5
  }

  belongs_to :user
  belongs_to :organization, optional: true

  scope :suspicious, -> { where(event_type: [:authorization_denied, :prompt_injection_detected]) }
  scope :by_user, ->(user) { where(user_id: user.id) }
  scope :recent, -> { order(created_at: :desc) }
end

# In controllers and services:
SecurityAudit.create!(
  user_id: current_user.id,
  organization_id: current_organization.id,
  event_type: :data_accessed,
  resource_type: "SearchResult",
  resource_id: search_result.id,
  metadata: { query: query, results_count: results.count }
)
```

---

### 17.4 Message Rating System

**Status:** Not implemented - ADD THIS ✅

Implement user feedback mechanism to track response quality:

```ruby
# app/models/message_feedback.rb (new)
class MessageFeedback < ApplicationRecord
  belongs_to :message
  belongs_to :user
  belongs_to :chat

  enum rating: { helpful: 1, neutral: 2, unhelpful: 3, harmful: 4 }
  enum feedback_type: { accuracy: 0, relevance: 1, clarity: 2, completeness: 3 }

  validates :rating, presence: true
  validates :user_id, :message_id, uniqueness: { scope: [:user_id, :message_id] }
end

# Database migration:
# db/migrate/TIMESTAMP_create_message_feedbacks.rb
class CreateMessageFeedbacks < ActiveRecord::Migration[8.0]
  def change
    create_table :message_feedbacks, id: :uuid do |t|
      t.uuid :message_id, null: false
      t.uuid :user_id, null: false
      t.uuid :chat_id, null: false
      t.integer :rating, null: false
      t.integer :feedback_type
      t.text :comment
      t.integer :helpfulness_score # 1-5 scale

      t.timestamps
    end

    add_index :message_feedbacks, [:message_id, :user_id], unique: true
    add_index :message_feedbacks, [:user_id, :created_at]
    add_index :message_feedbacks, [:chat_id]
    add_index :message_feedbacks, :rating

    add_foreign_key :message_feedbacks, :messages
    add_foreign_key :message_feedbacks, :users
    add_foreign_key :message_feedbacks, :chats
  end
end

# app/models/message.rb (enhancement)
class Message < ApplicationRecord
  has_many :feedbacks, class_name: "MessageFeedback"

  def average_rating
    feedbacks.average(:helpfulness_score).to_f.round(2)
  end

  def feedback_summary
    {
      total_ratings: feedbacks.count,
      average_rating: average_rating,
      helpful_count: feedbacks.where(rating: :helpful).count,
      unhelpful_count: feedbacks.where(rating: :unhelpful).count,
      harmful_reports: feedbacks.where(rating: :harmful).count
    }
  end
end
```

**UI Component for Rating:**

```erb
<!-- app/views/message_templates/_message_footer.html.erb -->
<div class="message-footer flex items-center gap-3 mt-2 text-sm text-gray-600">
  <div class="flex items-center gap-2" data-controller="message-rating" data-message-id="<%= message.id %>">
    <span class="text-xs">Was this helpful?</span>

    <button class="hover:text-green-600 transition-colors" data-action="message-rating#rate" data-rating="helpful">
      <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M14 10h4.764a2 2 0 011.789 2.894l-3.646 7.23a2 2 0 01-1.788 1.106H7a2 2 0 01-2-2V9a6 6 0 0112-3z"></path>
      </svg>
    </button>

    <button class="hover:text-red-600 transition-colors" data-action="message-rating#rate" data-rating="unhelpful">
      <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M10 14H5.236a2 2 0 01-1.789-2.894l3.646-7.23a2 2 0 011.788-1.106H17a2 2 0 012 2v7a6 6 0 01-12 3z"></path>
      </svg>
    </button>

    <!-- Report as harmful -->
    <button class="hover:text-orange-600 transition-colors ml-auto" data-action="click->message-rating#showReportModal">
      <svg class="w-4 h-4" fill="none" stroke="currentColor" viewBox="0 0 24 24">
        <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M12 9v2m0 4v2m0 4v2m0 0a9 9 0 11-18 0 9 9 0 0118 0z"></path>
      </svg>
    </button>
  </div>

  <% if message.feedbacks.count > 0 %>
    <div class="text-xs text-gray-500">
      <%= "#{message.average_rating}/5 (#{message.feedbacks.count} ratings)" %>
    </div>
  <% end %>
</div>
```

**Stimulus Controller:**

```javascript
// app/javascript/controllers/message_rating_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static values = {
    messageId: String,
    chatId: String
  }

  rate(event) {
    event.preventDefault()
    const rating = event.currentTarget.dataset.rating

    const formData = new FormData()
    formData.append("rating", rating)
    formData.append("message_id", this.messageIdValue)
    formData.append("chat_id", this.chatIdValue)

    fetch("/chat/message_feedbacks", {
      method: "POST",
      body: formData,
      headers: { "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content }
    })
    .then(response => response.json())
    .then(data => {
      if (data.success) {
        this.showFeedbackConfirmation(rating)
      }
    })
  }

  showFeedbackConfirmation(rating) {
    // Show brief confirmation message
    console.log(`Thanks for the feedback! Message marked as ${rating}`)
  }

  showReportModal(event) {
    event.preventDefault()
    // Open modal for detailed report (harmful content)
  }
}
```

**Controller for Rating Submission:**

```ruby
# app/controllers/chat/message_feedbacks_controller.rb (new)
module Chat
  class MessageFeedbacksController < ApplicationController
    before_action :authenticate_user!
    before_action :set_message

    def create
      @feedback = @message.feedbacks.build(feedback_params)
      @feedback.user = current_user
      @feedback.chat = @message.chat

      if @feedback.save
        # Track in security audit
        SecurityAudit.create!(
          user_id: current_user.id,
          organization_id: current_organization.id,
          event_type: :message_feedback_submitted,
          metadata: { rating: @feedback.rating, message_id: @message.id }
        )

        render json: { success: true, feedback: @feedback }
      else
        render json: { success: false, errors: @feedback.errors }, status: :unprocessable_entity
      end
    end

    private

    def set_message
      @message = Message.find(params[:message_id])
      authorize @message.chat # Ensure user can access this chat
    end

    def feedback_params
      params.require(:message_feedback).permit(:rating, :feedback_type, :comment)
    end
  end
end
```

---

### 17.5 Input Validation & Sanitization

**Current State:** Partial (needs enhancement)

```ruby
# app/validators/prompt_safety_validator.rb (new)
class PromptSafetyValidator < ActiveModel::Validator
  MAX_MESSAGE_LENGTH = 4000
  MAX_CONSECUTIVE_SPECIAL_CHARS = 10
  MAX_URL_COUNT = 5

  def validate(record)
    content = record.content.to_s

    # 1. Length check
    if content.length > MAX_MESSAGE_LENGTH
      record.errors.add :content, "is too long (max #{MAX_MESSAGE_LENGTH} chars)"
    end

    # 2. Check for excessive special characters (spam/noise)
    if content.scan(/[!@#$%^&*()_+=\[\]{};:'",.<>?/\\|`~-]/).length > MAX_CONSECUTIVE_SPECIAL_CHARS
      record.errors.add :content, "contains too many special characters"
    end

    # 3. Check for excessive URLs (potential phishing)
    url_count = content.scan(%r{https?://}).length
    if url_count > MAX_URL_COUNT
      record.errors.add :content, "contains too many URLs"
    end

    # 4. Check for potential SQL injection patterns
    if looks_like_sql_injection?(content)
      record.errors.add :content, "contains suspicious SQL patterns"
    end

    # 5. Check for common prompt injection keywords
    if contains_prompt_instructions?(content)
      record.errors.add :content, "appears to contain prompt injection attempts"
    end
  end

  private

  def looks_like_sql_injection?(content)
    sql_patterns = [
      /(\b(SELECT|INSERT|UPDATE|DELETE|DROP|CREATE|ALTER)\b)/i,
      /(-{2}|\/\*|\*\/)/,  # SQL comments
      /('|")(.*?)(OR|AND)/i # Quote escapes
    ]

    sql_patterns.any? { |pattern| content.match?(pattern) }
  end

  def contains_prompt_instructions?(content)
    injection_keywords = [
      "ignore", "forget", "pretend", "act as", "you are", "system prompt",
      "instructions", "administrator", "bypass", "jailbreak", "exploit"
    ]

    downcase = content.downcase
    injection_keywords.any? { |keyword| downcase.include?(keyword) }
  end
end

# app/models/message.rb (enhancement)
class Message < ApplicationRecord
  validates :content, prompt_safety: true
end
```

---

### 17.6 Security Implementation Checklist

Add these to your implementation plan:

**Phase 0: Security Foundation (Start immediately)**

- [ ] Add SecurityLog and ModerationLog models
- [ ] Add PromptInjectionDetector service
- [ ] Add PromptSafetyValidator
- [ ] Add MessageFeedback model + migration
- [ ] Enhance AiAgentMcpService with injection detection
- [ ] Create SecurityAudit model + migration
- [ ] Add security audit logging throughout

**Phase X: Monitoring & Response**

- [ ] Create admin dashboard for moderation review
- [ ] Implement security alerts for high-risk activities
- [ ] Create escalation workflow for reported content
- [ ] Add analytics for prompt injection attempts
- [ ] Build response quality dashboard (using message feedbacks)

**Phase X: Advanced Features (Future)**

- [ ] Token counting before processing (avoid DDoS)
- [ ] Response quality scoring (automatic)
- [ ] Sentiment analysis for concerning messages
- [ ] Pattern detection for repeated abuse
- [ ] User reputation scoring

---

### 17.7 Monitoring & Analytics Dashboard

Create an admin dashboard to track:

```ruby
# app/controllers/admin/security_dashboard_controller.rb
class Admin::SecurityDashboardController < ApplicationController
  before_action :authorize_admin

  def index
    @moderation_stats = {
      total_flagged: ModerationLog.where(flagged: true).count,
      flagged_today: ModerationLog.where(flagged: true).where("created_at > ?", 1.day.ago).count,
      by_category: ModerationLog.where(flagged: true).group_by { |m| m.categories }.map { |k, v| [k, v.count] }
    }

    @injection_stats = {
      total_detected: SecurityLog.where(event_type: :prompt_injection_detected).count,
      high_risk: SecurityLog.where(event_type: :prompt_injection_detected, risk_level: "high").count,
      trends: SecurityLog.group_by_day(:created_at).count
    }

    @response_quality = {
      avg_rating: MessageFeedback.average(:helpfulness_score),
      total_ratings: MessageFeedback.count,
      helpful_percentage: (MessageFeedback.where(rating: :helpful).count.to_f / MessageFeedback.count * 100).round(2),
      harmful_reports: MessageFeedback.where(rating: :harmful).count
    }

    @rate_limit_violations = RateLimitLog.where("created_at > ?", 1.day.ago).count
  end
end
```

---

## Part 18: Open Questions & Decisions

Before implementation starts, clarify:

1. **Chat Folders/Organization?**
   - Keep all chats in flat list?
   - Add folder/category organization?
   - Add automatic grouping by date/type?

2. **Commands Scope?**
   - Which "/" commands are most valuable?
   - Should commands vary by context (team vs. dashboard)?
   - Need command aliases?

3. **Mentions & References?**
   - Should "@" send context to LLM about person?
   - Should "#" scope chat to that resource?
   - Store references for analytics?

4. **File Upload Limits?**
   - Max file size per message? (suggest 10MB)
   - Max files per message? (suggest 5)
   - File type restrictions?

5. **Mobile Experience?**
   - Floating chat on mobile (or full-width?)
   - Simplified command palette?
   - Touch-friendly file upload?

6. **Chat Settings?**
   - Move RAG toggle here?
   - Model selection?
   - Temperature/params?
   - System prompt customization?

7. **Analytics & Logging?**
   - Track command usage?
   - Log file processing metrics?
   - Measure search relevance?

---

## Summary

This updated architecture addresses your three key requirements:

### 1. Search Discovery

✅ **Explicit `/search` command** (not auto-detected)
- Clarity: Users know exactly what's happening
- Predictable: Same input = same output
- Powerful: Can add advanced options `/search budget --sort:recent`
- Keeps natural conversation for questions: "What's our Q4 status?"

### 2. Markdown & Templates

✅ **Full markdown support** across all messages
- Code blocks with syntax highlighting
- Tables, lists, links, images, blockquotes
- Safe rendering with sanitization

✅ **Extensible template system** for rich message types
- User profiles, team summaries, org stats
- List/item creation cards
- Search results cards
- Command results formatted nicely
- Extend with new templates as needed

### 3. "New Chat" Button

✅ **Prominent "New Chat" button** always accessible
- Creates new Chat record
- Shows empty state with command suggestions
- Context-aware suggestions (what you're viewing)
- Auto-focuses input for immediate typing

### Overall Benefits

✅ **Consolidates** dual chat implementations into one unified system
✅ **Modernizes** UI to professional ChatGPT/Claude standard
✅ **Empowers** users with explicit "/" commands and extensible templates
✅ **Enhances** context awareness for smarter LLM interactions
✅ **Enables** file uploads and rich media support
✅ **Improves** chat discovery with history browser and new chat button
✅ **Maintains** excellent error handling and reliability
✅ **Preserves** existing RAG and organization scoping
✅ **Supports** phased rollout and backward compatibility

The implementation is substantial but well-scoped with clear phases. Your current foundations are excellent and will serve as the base for these enhancements.

**Estimated timeline:** 4-5 weeks for full implementation
**Complexity:** Medium (lots of new UI, moderate business logic changes)
**Risk:** Low (can be rolled out gradually with feature flags)
