# Claude.md - Listopia Development Quick Reference

Rails 8.1: collaborative list mgmt, Hotwire, AI chat, real-time collab.

## Stack
- Rails 8.1 w/ Solid Queue, Cache, Cable
- Ruby 3.4.7 w/ UUID PKs
- PostgreSQL 15+, RubyLLM 1.11+ (GPT-5)
- Hotwire (Turbo Streams + Stimulus)
- Tailwind CSS 4.1, Bun package mgr
- RSpec + Capybara testing

## Architecture

**Multi-Tenant w/ Organizations**
- User → Organization → Team (optional) → Lists
- All queries scoped to org (use `policy_scope`)
- See: [ORGANIZATIONS_TEAMS.md](docs/ORGANIZATIONS_TEAMS.md)

**Organization Context & Current Organization**
- **Critical**: Every user MUST belong to ≥1 org
- Org selection in nav bar (single place)
- Use `Current.organization` in any controller/service
- **Never** add local org selectors in views (nav bar only)
- No org selected? Redirect to root w/ alert
- Pattern: `redirect_to root_path, alert: "Please select an organization first" unless Current.organization`
- See: [ORGANIZATIONS_TEAMS.md](docs/ORGANIZATIONS_TEAMS.md)

**Real-Time Collaboration**
- Prefer Turbo Streams for reactive UI
- Use Stimulus only when Turbo can't solve
- See: [REAL_TIME.md](docs/REAL_TIME.md)

**Authorization**
- Rails 8 `has_secure_password`, magic link tokens
- Pundit policies: always `authorize @resource`
- See: [AUTHENTICATION.md](docs/AUTHENTICATION.md)

**AI Chat & List Creation** (Domain-Agnostic)
- Unified chat for natural language list creation/mgmt
- Chat context for semantic state persistence across messages
- LLM intent detection, complexity analysis, pre-creation planning
- Works w/ ANY list type (events, projects, reading, courses, recipes, travel, learning, personal, etc.)
  - No hardcoded domains; works equally for any domain
  - `ParameterMapperService` detects subdivision strategies via LLM
  - `HierarchicalItemGenerator` creates subdivisions (locations, books, modules, topics, phases, etc.)
  - Parent items generated dynamically per planning domain & context
  - `ItemGenerationService` generates context-appropriate items for any subdivision
- Real-time UI feedback: state indicator, progress, list preview, confirm
- Built-in security: prompt injection detection, content moderation
- Docs: [CHAT_CONTEXT.md](docs/CHAT_CONTEXT.md), [CHAT_FLOW.md](docs/CHAT_FLOW.md), [CHAT_REQUEST_TYPES.md](docs/CHAT_REQUEST_TYPES.md), [ITEM_GENERATION.md](docs/ITEM_GENERATION.md)

## Common Patterns

**Query Scoping (Critical)**
```ruby
policy_scope(List)  # Returns only user's org lists
current_organization.lists  # Access through org
.where(organization_id: current_user.organizations.select(:id))  # Explicit filter
```

**Organization Context (Critical)**
```ruby
# In controllers - ensure organization is selected
@organization = Current.organization
redirect_to root_path, alert: "Select organization" unless @organization

# In models/services - access the current context
Event.where(organization_id: Current.organization.id)

# For admin/audit features - verify org is set
redirect_to admin_root_path, alert: "Please select an organization first" unless @organization
```

**Authorization**
```ruby
authorize @list  # Use Pundit on every action
```

**Turbo Stream Response**
```erb
<%= turbo_stream.replace(@list) { render "list", list: @list } %>
```

**Service Pattern**
```ruby
class MyService < ApplicationService
  def call
    # Return success(data: ...) or failure(errors: ...)
  end
end
```

## Key Files
- Models w/ UUID: `app/models/`, FKs as UUID
- Auth policies: `app/policies/`
- Complex logic: `app/services/` (inherit ApplicationService)
- Tests: RSpec w/ Factory Bot, Faker
- Database: PostgreSQL w/ pgcrypto, plpgsql
  - Uses `db/structure.sql` (not schema.rb) — enforced by user change tracking service
  - All models annotated w/ `annotate` gem: see Schema Info at top of each model

## Pagination (Pagy v43+)

**CRITICAL: Pagy v43+ has major breaking changes from previous versions**

Project uses Pagy v43.3.2 w/ restructured API. Don't rely on old Pagy docs or pre-v43 examples.

**Key Differences:**
- ❌ No `pagy_nav` method (old)
- ✅ Use `series_nav` for numeric pagination (need `include Pagy::NumericHelpers` in helpers)
- ❌ Old helper methods renamed/removed
- ✅ View helpers must be explicitly included: `include Pagy::NumericHelpers` in ApplicationHelper

**Available Pagy v43+ View Helpers** (from `Pagy::NumericHelpers`):
- `series_nav(@pagy)` - Numeric pagination w/ prev/next links
- `series_nav_js(@pagy)` - JS-powered pagination
- `info_tag(@pagy)` - Shows "Displaying X of Y"
- `previous_tag(@pagy)` - Previous page link
- `input_nav_js(@pagy)` - Jump to page input

**How to Use:**
```erb
<!-- Instead of old: <%= pagy_nav(@pagy) %> -->
<!-- Use: -->
<%= series_nav(@pagy) %>
```

**Common Patterns:**
```ruby
# In controller:
include Pagy::Method  # Adds pagy method for backend

# In helper:
include Pagy::NumericHelpers  # Adds series_nav, info_tag, etc. for views

# In view:
@pagy, @items = pagy(collection)
<%= series_nav(@pagy) %>
```

**Before implementing Pagy features:**
1. Check [Pagy v43 official docs](https://ddnexus.github.io/pagy/): Method names & APIs NOT compatible w/ older tutorials
2. Look for existing usage in `app/views/` to match patterns
3. Unsure about method name? Check `lib/pagy/toolbox/helpers/loaders.rb` for available methods

## Development

**Ruby LSP Integration**
- Ruby LSP plugin installed in Claude Code
- Use LSP tools for code navigation & analysis:
  - `goToDefinition` - Find symbol definition
  - `findReferences` - Find all usages
  - `hover` - Get type info & docs
  - `documentSymbol` - List all symbols in file
  - `workspaceSymbol` - Search symbols across codebase
  - `goToImplementation` - Find implementations
  - `prepareCallHierarchy` / `incomingCalls` / `outgoingCalls` - Analyze call chains
- Useful for understanding service dependencies, model relationships, controller flows

**Quick Setup**
```bash
rails db:create db:migrate
bundle exec rspec
bun install && bun run build:css
```

**Code Quality**
```bash
bundle exec rubocop --fix    # Style
bundle exec brakeman         # Security
```

**Common Issues**
| Issue | Solution |
|-------|----------|
| N+1 Queries | Use `includes`, `preload`, or `joins` |
| Auth Failed | Call `authorize @resource` after load |
| Turbo not working | Respond w/ `format.turbo_stream` |
| Test DB issues | `RAILS_ENV=test rails db:reset` |
| No org selected | Select in nav bar; redirect if `Current.organization` nil |
| Cross-org data leak | Always scope queries w/ `organization_id`; use `Current.organization` |
| Org selector on view | Don't add local selectors; nav bar only |

## Detailed Docs

**Architecture & Design Principles** (START HERE)
- [ARCHITECTURE_GENERIC_DESIGN.md](docs/ARCHITECTURE_GENERIC_DESIGN.md) - **Critical**: Domain-agnostic design for ANY list type. Required reading.

**Chat Context System** (Consolidated Reference)
- [CHAT_CONTEXT.md](docs/CHAT_CONTEXT.md) - System overview: architecture, services, integration, UI components, testing & migration

**Chat System** (Integration w/ chat flow)
- [CHAT_FLOW.md](docs/CHAT_FLOW.md) - Message flow & state machine
- [CHAT_REQUEST_TYPES.md](docs/CHAT_REQUEST_TYPES.md) - Simple/complex/nested list handling
- [CHAT_MODEL_SELECTION.md](docs/CHAT_MODEL_SELECTION.md) - Model selection strategy
- [CHAT_FEATURES.md](docs/CHAT_FEATURES.md) - How to add features

**Core Features**
- [Database & Queries](docs/DATABASE.md)
- [Testing](docs/TESTING.md)
- [Organizations & Teams](docs/ORGANIZATIONS_TEAMS.md)
- [Real-Time Collaboration](docs/REAL_TIME.md)
- [Authentication](docs/AUTHENTICATION.md)
- [Notifications](docs/NOTIFICATION.md)

**Performance**
- [Performance Gems Setup](docs/PERFORMANCE_GEMS_SETUP.md)
- [N+1 Query Fixes](docs/n_plus_one_fixes.md)

**Other**
- [Search & RAG](docs/RAG_SEMANTIC_SEARCH.md)
- [Documentation Index](docs/README.md)

## Useful Commands
```bash
rails db:create db:migrate       # Setup dev DB
RAILS_ENV=test rails db:reset   # Reset test DB
bundle exec rspec               # Run tests
rails g stimulus ControllerName # Create Stimulus controller
kamal deploy                     # Deploy changes
```

## External Resources
- [Rails 8 Guides](https://guides.rubyonrails.org/)
- [Hotwire](https://hotwired.dev/)
- [Pundit](https://github.com/varvet/pundit)
- [RSpec Rails](https://github.com/rspec/rspec-rails)