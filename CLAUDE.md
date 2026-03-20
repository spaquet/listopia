# Claude.md - Listopia Development Quick Reference

Rails 8.1 collaborative list management with Hotwire, AI-powered chat, and real-time collaboration.

## Stack
- **Rails 8.1** with Solid Queue, Cache, Cable
- **Ruby 3.4.7** with UUID primary keys
- **PostgreSQL 15+**, RubyLLM 1.11+ (GPT-5)
- **Hotwire** (Turbo Streams + Stimulus)
- **Tailwind CSS 4.1**, Bun package manager
- **RSpec + Capybara** for testing

## Architecture

**Multi-Tenant with Organizations**
- User → Organization → Team (optional) → Lists
- All queries scoped to organization (use `policy_scope`)
- See: [ORGANIZATIONS_TEAMS.md](docs/ORGANIZATIONS_TEAMS.md)

**Organization Context & Current Organization**
- **Critical Requirement**: Every user MUST belong to at least one organization
- Organization selection happens in the navigation bar (single place)
- Use `Current.organization` to access the current organization in any controller/service
- **Never** implement local organization selectors in views (use the nav bar selector)
- If no organization is selected, redirect to dashboard/root with alert
- Pattern: `redirect_to root_path, alert: "Please select an organization first" unless Current.organization`
- See: [ORGANIZATIONS_TEAMS.md](docs/ORGANIZATIONS_TEAMS.md)

**Real-Time Collaboration**
- Prefer Turbo Streams for all reactive UI
- Use Stimulus only when Turbo can't solve it
- See: [REAL_TIME.md](docs/REAL_TIME.md)

**Authorization**
- Rails 8 `has_secure_password`, magic link tokens
- Pundit policies: always `authorize @resource`
- See: [AUTHENTICATION.md](docs/AUTHENTICATION.md)

**AI Chat & List Creation**
- Unified chat interface for natural language list creation and management
- LLM-powered intent detection, complexity analysis, and pre-creation planning
- Built-in security: prompt injection detection, content moderation
- See: [CHAT_FLOW.md](docs/CHAT_FLOW.md), [CHAT_REQUEST_TYPES.md](docs/CHAT_REQUEST_TYPES.md), [CHAT_MODEL_SELECTION.md](docs/CHAT_MODEL_SELECTION.md), [CHAT_FEATURES.md](docs/CHAT_FEATURES.md)

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
- Models with UUID: `app/models/`, foreign keys as UUID
- Authorization policies: `app/policies/`
- Complex logic: `app/services/` (inherit ApplicationService)
- Tests: RSpec with Factory Bot, Faker
- Database: PostgreSQL with pgcrypto, plpgsql
  - Uses `db/structure.sql` (not schema.rb) — enforced by user change tracking service
  - All models annotated with `annotate` gem: see Schema Information at top of each model

## Pagination (Pagy v43+)

**CRITICAL: Pagy v43+ has major breaking changes from previous versions**

This project uses **Pagy v43.3.2**, which has completely restructured its API. Do NOT rely on old Pagy documentation or examples from pre-v43 versions.

**Key Differences:**
- ❌ No `pagy_nav` method (was common in older versions)
- ✅ Use `series_nav` for numeric pagination (requires `include Pagy::NumericHelpers` in helpers)
- ❌ Old helper methods are renamed/removed
- ✅ View helpers must be explicitly included: `include Pagy::NumericHelpers` in ApplicationHelper

**Available Pagy v43+ View Helpers** (from `Pagy::NumericHelpers`):
- `series_nav(@pagy)` - Numeric pagination with previous/next links
- `series_nav_js(@pagy)` - JavaScript-powered pagination
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

**Before implementing any Pagy features:**
1. Check [Pagy v43 official docs](https://ddnexus.github.io/pagy/): Method names and APIs are NOT compatible with older tutorials
2. Look for existing usage in `app/views/` to match patterns
3. If unsure about a method name, check `lib/pagy/toolbox/helpers/loaders.rb` for available methods

## Development

**Ruby LSP Integration**
- Ruby LSP plugin is installed in Claude Code
- Use LSP tools for code navigation and analysis:
  - `goToDefinition` - Find where a symbol is defined
  - `findReferences` - Find all usages of a symbol
  - `hover` - Get type info and documentation
  - `documentSymbol` - List all symbols in a file
  - `workspaceSymbol` - Search symbols across codebase
  - `goToImplementation` - Find implementations of interfaces/methods
  - `prepareCallHierarchy` / `incomingCalls` / `outgoingCalls` - Analyze call chains
- Useful for understanding service dependencies, model relationships, and controller flows

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
| Turbo not working | Respond with `format.turbo_stream` |
| Test DB issues | `RAILS_ENV=test rails db:reset` |
| No organization selected | User must select one in nav bar; redirect if `Current.organization` is nil |
| Cross-org data leak | Always scope queries with `organization_id`; use `Current.organization` |
| Organization selector on view | Don't add local selectors; use nav bar only |

## Detailed Docs

**Chat System** (Start here for AI features)
- [CHAT_FLOW.md](docs/CHAT_FLOW.md) - Complete message flow & state machine
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
