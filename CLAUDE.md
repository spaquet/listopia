# Claude.md - Listopia Development Guide

Quick reference for developing Listopia, a modern Rails 8 collaborative list management application.

## Stack Overview

- **Rails 8.1** with Solid Queue, Solid Cache, Solid Cable
- **Ruby 3.4.7** with UUID primary keys
- **PostgreSQL 15+** for database
- **Hotwire** (Turbo Streams + Stimulus) for real-time updates
- **Tailwind CSS 4.1** with Bun package manager
- **RubyLLM 1.8+** for AI chat integration
- **RSpec + Capybara + Factory Bot** for testing
- **Kamal + Docker** for deployment

## Architecture Patterns

### Authentication & Authorization
- Rails 8 authentication with `has_secure_password`
- Magic link tokens via `generates_token_for`
- Email verification on signup
- Pundit policies for authorization (always use `authorize @resource`)
- Rolify for role-based access control

### Database Conventions
- **All models use UUID primary keys** (never integers)
- Foreign keys are UUID type
- PostgreSQL extensions: `pgcrypto`, `plpgsql`
- Strategic indexes on common query paths
- JSONB metadata columns for flexibility

### Controller & Model Organization
- RESTful controllers with proper authorization checks
- Service objects for complex business logic (McpService, ListSharingService)
- Enums for status/priority fields
- Soft deletes with `discard` gem where needed

### Real-Time & Interactivity Philosophy
- **Prefer Turbo Streams** for all real-time updates and reactive UI
- Use Stimulus controllers only when Turbo Streams cannot solve the problem
- All UIs are responsive and mobile-first
- Respond with `turbo_stream` format from controllers
- Trigger broadcasts for multi-user real-time collaboration

## Key Models

```ruby
# User - authentication & account
belongs_to :current_chat (optional)
has_many :lists (owner_id), :sessions, :chats, :messages

# List - collaborative document
belongs_to :owner (User), has_many :list_items, :list_collaborations, :list_tags
enum :status (draft, active, completed, archived)

# ListItem - tasks/content
belongs_to :list, :assigned_user (optional)
enum :priority (low, medium, high)
enum :status (pending, in_progress, completed)

# ListCollaboration - sharing & permissions
belongs_to :list, :user (optional)
enum :permission (view, comment, edit, admin)

# Chat - AI conversations
belongs_to :user
has_many :messages
enum :status (active, archived, completed)

# Message - chat history
belongs_to :chat, :user (optional for assistant messages)
enum :role (user, assistant, system, tool)
```

## Frontend Approach

**Turbo-First Philosophy:** Build features with Turbo Streams and Turbo Frames whenever possible. JavaScript (via Stimulus) is a last resort for interactions that Turbo cannot handle.

- **Turbo Streams** handle real-time updates, partial replacements, and reactive UI
- **Stimulus Controllers** only for DOM interactions Turbo cannot solve (animations, complex state, third-party integrations)
- **Responsive Design** - All UIs use Tailwind's responsive utilities (mobile-first)
- **Progressive Enhancement** - Features work without JavaScript, enhanced with interactivity

### File Structure
```
app/
  models/           # UUID-based models with proper associations
  controllers/      # RESTful with Pundit authorization
  services/         # Complex business logic (McpService, etc)
  policies/         # Pundit authorization policies
  views/
    shared/         # Shared partials
    [resource]/     # Resource-specific templates
  javascript/
    controllers/    # Stimulus JS controllers
    
config/
  routes.rb         # RESTful routes with namespacing
  
db/
  migrate/          # Always enable pgcrypto, use UUIDs
```

### Common Tasks

**Create a model with UUID:**
```ruby
rails g model List owner:references title:string status:string
# Modify migration: id: :uuid, foreign_key: { type: :uuid }
```

**Add authorization:**
```ruby
# In controller: before_action :authorize_list_access!
# Create app/policies/list_policy.rb with show?, edit?, destroy? methods
authorize @list  # Use Pundit for every action
```

**Real-time update (Turbo Stream - preferred):**
```erb
<%= turbo_stream.replace(@list) do %>
  <%= render "list", list: @list %>
<% end %>
```

**Complex interaction (Stimulus - use only when needed):**
```javascript
// app/javascript/controllers/dropdown_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu"]
  
  toggle() {
    this.menuTarget.classList.toggle("hidden")
  }
}
```

**Responsive design (Tailwind - always):**
```erb
<div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
  <div class="p-4 bg-white rounded-lg">Mobile-first responsive</div>
</div>
```

## Performance & Quality

### Database
- Use `includes`, `joins`, `preload` to prevent N+1 queries
- Index foreign keys and frequently queried columns
- Pagination with Pagy for large datasets
- Cache expensive operations with Solid Cache

### Code Quality
- RuboCop Omakase enforces style
- Brakeman checks for security issues
- Bullet gem prevents N+1 queries in development
- Keep controllers thin, push logic to models/services

### Testing
- Model specs for validations & associations
- Controller specs for authorization & responses
- Integration/system specs for user workflows
- Use Factory Bot for test data, Faker for random values

## Common Issues & Solutions

**N+1 Queries:** Use `includes` when loading associations  
**Authorization Failed:** Always call `authorize` after loading resource  
**UUID Errors:** Ensure migration uses `id: :uuid` and `type: :uuid` for FKs  
**Turbo Stream Not Working:** Check format responds with `format.turbo_stream`  
**Test Database Issues:** Run `RAILS_ENV=test rails db:reset`

## Useful Commands

```bash
# Database
rails db:create db:migrate       # Setup dev database
RAILS_ENV=test rails db:reset   # Reset test database

# Testing
bundle exec rspec               # Run all tests
bundle exec rspec spec/models   # Run model tests only

# Code Quality
bundle exec rubocop --fix       # Auto-fix style issues
bundle exec brakeman            # Security check

# Frontend
bun install                      # Install JS dependencies
bun run build:css               # Compile Tailwind

# Deployment
kamal setup                      # Initial deployment
kamal deploy                     # Deploy changes
```

## External Resources

- [Rails 8 Guides](https://guides.rubyonrails.org/)
- [Hotwire Documentation](https://hotwired.dev/)
- [Pundit Authorization](https://github.com/varvet/pundit)
- [RSpec Rails](https://github.com/rspec/rspec-rails)