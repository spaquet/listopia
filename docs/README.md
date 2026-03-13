# Listopia Developer Documentation

Technical reference for developers and AI coding agents contributing to Listopia.

**Rails 8** collaborative list management with real-time Hotwire, AI-powered chat (GPT-5), and permission-based collaboration.

---

## 🎯 Quick Start by Task

### Understanding the System
- **Start here**: [CHAT_FLOW.md](./CHAT_FLOW.md) - Complete chat message flow
- Then read: [CHAT_REQUEST_TYPES.md](./CHAT_REQUEST_TYPES.md) - Simple/complex/nested lists
- For model details: [CHAT_MODEL_SELECTION.md](./CHAT_MODEL_SELECTION.md) - Why gpt-4.1-nano vs gpt-5

### Adding Chat Features
- [CHAT_FEATURES.md](./CHAT_FEATURES.md) - How to add commands, tools, templates
- [CHAT_FLOW.md](./CHAT_FLOW.md) - Message routing & orchestration
- Code refs: `app/services/chat_*.rb`

### Optimizing Performance
- [CHAT_MODEL_SELECTION.md](./CHAT_MODEL_SELECTION.md) - Cost vs latency trade-offs
- [PERFORMANCE_GEMS_SETUP.md](./PERFORMANCE_GEMS_SETUP.md) - Profiling tools

### Working with Lists
- [DATABASE.md](./DATABASE.md) - Schema & query patterns
- [TESTING.md](./TESTING.md) - Test patterns

### Real-time Collaboration
- [REAL_TIME.md](./REAL_TIME.md) - Turbo Streams & live updates
- [COLLABORATION.md](./COLLABORATION.md) - Multi-user permissions
- [ORGANIZATIONS_TEAMS.md](./ORGANIZATIONS_TEAMS.md) - Org/team scoping

### Authentication & Authorization
- [AUTHENTICATION.md](./AUTHENTICATION.md) - Auth system & magic links
- [ORGANIZATIONS_TEAMS.md](./ORGANIZATIONS_TEAMS.md) - Org boundaries & policy scope

### RAG & Semantic Search
- [RAG_SEMANTIC_SEARCH.md](./RAG_SEMANTIC_SEARCH.md) - Knowledge base & search

---

## 📚 Complete Documentation Map

### Chat System (Unified AI Chat Interface)

| Document | Topic | Use When |
|----------|-------|----------|
| [CHAT_FLOW.md](./CHAT_FLOW.md) | Complete message flow, state machine, 6 scenarios | Understanding how chat works |
| [CHAT_REQUEST_TYPES.md](./CHAT_REQUEST_TYPES.md) | Simple/complex/nested lists, commands, navigation | Understanding different request types |
| [CHAT_MODEL_SELECTION.md](./CHAT_MODEL_SELECTION.md) | Why gpt-4.1-nano, when to use gpt-5 | Optimizing models, understanding performance |
| [CHAT_FEATURES.md](./CHAT_FEATURES.md) | How to add features, tools, templates, commands | Implementing new chat capabilities |

### Core Features

| Document | Topic | Lines | Purpose |
|----------|-------|-------|---------|
| [DATABASE.md](./DATABASE.md) | Schema, queries, N+1 fixes | ~500 | Database design & patterns |
| [REAL_TIME.md](./REAL_TIME.md) | Turbo Streams, live updates | ~400 | Real-time collaboration |
| [COLLABORATION.md](./COLLABORATION.md) | Multi-user sharing, permissions | ~800 | List sharing & access control |
| [ORGANIZATIONS_TEAMS.md](./ORGANIZATIONS_TEAMS.md) | Org/team scoping, hierarchy | ~600 | Multi-tenant architecture |
| [AUTHENTICATION.md](./AUTHENTICATION.md) | Auth system, magic links | ~400 | User authentication |

### Performance & Optimization

| Document | Topic | Purpose |
|----------|-------|---------|
| [OPTIMIZATION_VISUAL_GUIDE.md](./OPTIMIZATION_VISUAL_GUIDE.md) | Before/after comparisons | Visualizing improvements |
| [PERFORMANCE_GEMS_SETUP.md](./PERFORMANCE_GEMS_SETUP.md) | Profiling tools (bullet, rack-mini-profiler) | Finding bottlenecks |
| [n_plus_one_fixes.md](./n_plus_one_fixes.md) | Query optimization examples | Fixing N+1 queries |

### Testing & Development

| Document | Topic | Purpose |
|----------|-------|---------|
| [TESTING.md](./TESTING.md) | RSpec patterns, test organization | Writing tests |

### Search & Knowledge Base

| Document | Topic | Purpose |
|----------|-------|---------|
| [RAG_SEMANTIC_SEARCH.md](./RAG_SEMANTIC_SEARCH.md) | Semantic search, knowledge base | RAG integration |

---

## 🏗️ Architecture Overview

### Core Stack
- **Backend**: Rails 8.1 with UUID primary keys
- **Database**: PostgreSQL 15+ with pgcrypto
- **Frontend**: Hotwire (Turbo Streams + Stimulus) + Tailwind CSS 4.1
- **AI**: RubyLLM 1.11+ (OpenAI GPT-5, Claude, Gemini)
- **Jobs**: Solid Queue for background processing
- **Real-time**: Turbo Streams over WebSocket
- **Authorization**: Pundit + Rolify

### Multi-Tenant Architecture
```
Organization
├── Teams (optional)
├── Users
├── Lists
│   ├── ListItems
│   ├── ListCollaborations
│   └── SubLists (nested)
└── Chats
    └── Messages
```

### Scoping Pattern (Critical)
```ruby
# All queries scoped to organization
policy_scope(List)  # Returns only current user's org lists
current_organization.lists  # Access through org
.where(organization_id: current_user.organizations.select(:id))
```

---

## 🤖 AI Chat System

### Unified Chat Interface
Single chat for all interactions: list creation, resource management, navigation, general questions.

### Intent Detection (gpt-4.1-nano)
- **create_list** - Plan, project, list creation
- **create_resource** - Add user, team, organization
- **navigate_to_page** - Go to a page
- **search_data** - Find something
- **manage_resource** - Update/delete
- **general_question** - Anything else (LLM + tools)

### Request Types
1. **Simple Lists** → Create immediately (1-2s)
2. **Complex Lists** → Ask clarifying questions first (2-3s)
3. **Nested Lists** → Create hierarchical structure with sub-lists (3-4s)
4. **Commands** → `/search`, `/help`, `/browse` (sync, <1s)
5. **Navigation** → Route to page (<1s)
6. **Resource Creation** → Collect parameters (2-3s)
7. **General Questions** → LLM + tools (2-3s)

### Optimization Strategy
- **CombinedIntentComplexityService** - Single LLM call (intent + complexity + params)
- **gpt-4.1-nano for classification** - 33% faster than gpt-5-nano
- **gpt-5 for critical features** - Reliability over speed for list refinement
- **Async processing** - Background jobs for non-blocking responses

See [CHAT_FLOW.md](./CHAT_FLOW.md) for complete flow.

---

## 📋 Key Concepts

### Lists & Items
- **List** - Owned by user, contains multiple items
- **ListItem** - Belongs to list, has status (pending/completed)
- **SubList** - Child list for hierarchical organization
- **Status**: draft → active → completed → archived

### Collaboration
- **ListCollaboration** - Manages sharing & permissions
- **Permissions**: read (view-only), write (full access)
- **Invitations**: Email-based with unique tokens
- **Real-time** - Turbo Streams broadcast changes

### Chat & Refinement
- **Pre-Creation Planning** - Ask questions before creating list (complex requests)
- **Post-Creation Refinement** - Ask questions after creation to enhance items
- **State Management** - Pending states stored in chat.metadata
- **Nested Structures** - Auto-create sub-lists for multi-location/phase projects

### Real-time Updates
- **Turbo Streams** - Push changes to all viewers
- **Stimulus Controllers** - Handle client interactions
- **Optimistic Updates** - Show changes before confirmation

---

## 🔐 Security & Authorization

### Authorization Patterns
```ruby
# Always use Pundit
authorize @list
authorize :admin_user, :read?

# Scope queries
policy_scope(List)  # Auto-filters by org
```

### Security Checks
- Prompt injection detection (PromptInjectionDetector)
- Content moderation (ContentModerationService)
- Organization boundaries (all queries scoped)
- Role-based access (Pundit policies)

See [AUTHENTICATION.md](./AUTHENTICATION.md) for details.

---

## 🚀 Performance Metrics

### Baseline (Unoptimized)
- Intent detection: 3.0 seconds
- Full chat flow: 5-8 seconds
- Database queries: 40+ per page

### After Optimization (Current)
- Intent detection: 2.0 seconds (33% faster)
- Full chat flow: 1-3 seconds (perceived)
- Database queries: 2-5 per page (95% reduction)
- Cost: 89% reduction per request

See [PERFORMANCE_GEMS_SETUP.md](./PERFORMANCE_GEMS_SETUP.md) for profiling tools.

---

## 🔧 Development Standards

### Code Organization
- **Models**: `app/models/` with UUID keys
- **Services**: `app/services/` for complex logic
- **Controllers**: RESTful + non-RESTful actions
- **Views**: Partials for reusable components
- **Tests**: RSpec with Factory Bot, Faker

### Patterns
- **Service Pattern**: Inherit ApplicationService, return success/failure
- **Turbo Streams**: Respond with turbo_stream format
- **Authorization**: Authorize after load
- **Query Scoping**: Use policy_scope or explicit org filter
- **Eager Loading**: Use includes/preload to prevent N+1

### Naming Conventions
- Services: `XxxService` (e.g., ChatCompletionService)
- Models: Singular, CamelCase (e.g., ListItem, ChatContext)
- Controllers: Plural, RESTful (e.g., ListsController)
- Enums: Descriptive values (draft, active, completed, archived)

---

## 🧪 Testing

### Test Organization
```
spec/
├── controllers/
├── models/
├── services/      ← Most AI/chat tests here
├── system/        ← Integration tests
└── factories/
```

### Common Patterns
```ruby
# Service test
result = ChatCompletionService.new(chat, message).call
expect(result.success?).to be true
expect(result.data[:intent]).to eq "create_list"

# Authorization test
expect { authorize @list }.not_to raise_error
expect { authorize other_list }.to raise_error(Pundit::NotAuthorizedError)

# Integration test (Capybara)
visit new_list_path
fill_in "Title", with: "My List"
click_button "Create"
```

See [TESTING.md](./TESTING.md) for comprehensive patterns.

---

## 🔍 Debugging & Monitoring

### Check Chat State
```ruby
chat = Chat.find("uuid")
chat.metadata  # Shows pending_pre_creation_planning, pending_list_refinement, etc.
```

### Monitor Performance
```bash
# Check logs
tail -f log/development.log | grep "ChatCompletionService"

# Profile requests
rack_mini_profiler (configured in PERFORMANCE_GEMS_SETUP.md)

# Find N+1 queries
bullet (detects in development)
```

### Debug Intent Detection
```ruby
result = CombinedIntentComplexityService.new(
  user_message: message,
  chat: chat,
  user: user,
  organization: org
).call
puts result.data.inspect
```

See [CHAT_FLOW.md](./CHAT_FLOW.md) for debugging section.

---

## 📞 Quick Reference by File

### Services (Chat)
- `chat_completion_service.rb` (1629 lines) - Main orchestrator
- `combined_intent_complexity_service.rb` - Intent + complexity + params (single call)
- `list_complexity_detector_service.rb` - Is list complex?
- `question_generation_service.rb` - Pre-creation planning questions
- `parameter_extraction_service.rb` - Extract parameters
- `list_refinement_service.rb` - Refinement questions
- `chat_resource_creator_service.rb` - Create lists/users/teams/orgs
- `chat_routing_service.rb` - Navigation intent detection
- `chat_mention_parser.rb` - Parse @mentions

### Models
- `chat.rb` - Conversation thread
- `message.rb` - Individual message
- `chat_context.rb` - Context object
- `list.rb` - List with items
- `list_item.rb` - Item in list

### Controllers
- `chats_controller.rb` - Chat interface
- `lists_controller.rb` - List management
- `list_items_controller.rb` - Item management

### Views
- `chats/show.html.erb` - Main chat page
- `chats/_unified_chat.html.erb` - Chat component
- `message_templates/*.html.erb` - Message rendering

---

## 📖 Development Workflow

### Adding a Feature
1. Create migration (if needed)
2. Update model/add validations
3. Implement service logic
4. Add controller action
5. Create view/template
6. Add Stimulus controller (if needed)
7. Write RSpec tests
8. Test real-time updates (Turbo Streams)

### Fixing a Bug
1. Write failing test
2. Debug with `puts`, `binding.pry`, or logs
3. Implement fix
4. Verify test passes
5. Check related tests
6. Test manually in browser

### Optimizing Performance
1. Profile with Rack Mini Profiler
2. Check for N+1 with Bullet
3. Implement fix (eager loading, caching, etc.)
4. Benchmark before/after
5. Monitor in production with New Relic (if available)

---

## 🔗 External Resources

- [Rails Guides](https://guides.rubyonrails.org/)
- [Hotwire](https://hotwired.dev/)
- [Pundit](https://github.com/varvet/pundit)
- [RSpec Rails](https://github.com/rspec/rspec-rails)
- [Tailwind CSS](https://tailwindcss.com/)
- [RubyLLM Docs](https://github.com/lewagon/ruby-llm)