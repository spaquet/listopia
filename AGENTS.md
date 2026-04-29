# Listopia Codebase Guide for AI Coding Agents

This is the code base of the Listopia Ruby on Rails application.

## Architecture Overview

This is a Ruby on Rails application with the following structure:

- **app/models** - Active Record models
- **app/views** - View templates (ERB, etc.)
- **app/controllers** - Controllers
- **app/services** - Service objects for business logic
- **app/queries** - Query objects for complex queries
- **app/jobs** - Background jobs
- **app/policies** - Pundit authorization policies
- **config/** - Application configuration
- **docs/** - Detailed documentation

## Tech Stack

- **Database**: PostgreSQL only (no Redis)
- **CSS**: Tailwind CSS 4 with Bun
- **Pagination**: Pagy v43+ (uses `series_nav`, not `pagy_nav`)
- **Components**: ViewComponent for reusable view components
- **JavaScript**: Hotwire (Turbo Streams) preferred over Stimulus
- **Stimulus Controllers**: Plain JavaScript (no TypeScript)

### UI Guidelines

- Prefer Turbo Stream responses for reactive UI over custom JavaScript
- Use Stimulus only when Turbo can't solve the problem
- All Stimulus controllers are plain JavaScript in `app/javascript/controllers/`

## Testing Commands

This project uses **RSpec** for testing with Capybara.

### Running Tests

```bash
bundle exec rspec                      # Run all specs
bundle exec rspec spec/                 # Run all specs
bundle exec rspec spec/models/          # Run model specs
bundle exec rspec spec/models/user_spec.rb
bundle exec rspec -e "test name"        # Filter by spec name
```

### Running Specific Specs

```bash
bundle exec rspec spec/models/user_spec.rb:10  # Run specific spec at line 10
```

## Code Conventions

### Service Objects

Favor service objects when implementing CRUD and related operations so that the methods can be used by controllers, APIs, background jobs, and other service objects. Services inherit from `ApplicationService` and live in `app/services/`. Name with the operation (e.g., `CreateList`, `UpdateUser`, `Finder`).

```ruby
class MyService < ApplicationService
  def call
    # Return success(data: ...) or failure(errors: ...)
  end
end
```

### Query Objects

Use query objects in `app/queries/` for complex database queries.

### Code Style

- Run RuboCop: `bundle exec rubocop` (there's a project-wide `.rubocop.yml`)
- Run Brakeman: `bundle exec brakeman` (security)
- Use `# frozen_string_literal: true` at top of all files

## Finding Related Code

- **Ruby LSP**: This project supports Ruby LSP for code navigation. Use your editor's LSP features for go-to-definition, find references, hover for type info, document symbols, and workspace symbols.
- **Models**: Look in `app/models/`
- **Services**: Check `app/services/` for business logic
- **Policies**: Check `app/policies/` for authorization
- **Queries**: Check `app/queries/` for complex queries
- **Configuration**: Check `config/` for application configuration

## Key Patterns

### Organization Scoping
```ruby
policy_scope(List)  # Returns only user's org lists
current_organization.lists  # Access through org
```

### Authorization
```ruby
authorize @list  # Use Pundit on every action
```

### Turbo Stream Response
```erb
<%= turbo_stream.replace(@list) { render "list", list: @list } %>
```

## File Organization Principles

- `app/models` - Active Record models (UUID primary keys)
- `app/views` - View templates (ERB, etc.)
- `app/controllers` - Controllers
- `app/services` - Service objects (inherit ApplicationService)
- `app/queries` - Query objects for complex queries
- `app/jobs` - Background jobs
- `app/policies` - Pundit authorization policies
- `config/` - Application configuration
- `spec/` - Test files using RSpec with Factory Bot, Faker
- `docs/` - Detailed documentation
- `bin/` - Executable scripts (e.g., `bin/dev`)

## Documentation

- Detailed documentation is in `docs/` folder
- See `docs/README.md` for documentation index
- Key docs: ARCHITECTURE_GENERIC_DESIGN.md, CHAT_CONTEXT.md, ORGANIZATIONS_TEAMS.md, AUTHENTICATION.md, REAL_TIME.md
- API docs use standard Rails conventions

## Quick Setup

```bash
rails db:create db:migrate
bundle exec rspec
bun install && bun run build:css
```

## Common Issues

| Issue | Solution |
|-------|----------|
| N+1 Queries | Use `includes`, `preload`, or `joins` |
| Auth Failed | Call `authorize @resource` after load |
| Turbo not working | Respond with `format.turbo_stream` |
| Test DB issues | `RAILS_ENV=test rails db:reset` |
| No org selected | Select in nav bar; redirect if `Current.organization` nil |
| Cross-org data leak | Always scope queries with `organization_id`; use `Current.organization` |

## Behavioral Guidelines for Coding

Reduce common mistakes. Bias toward clarity over speed. For trivial tasks, use judgment.

### 1. Think Before Coding

Don't assume. Surface confusion and tradeoffs explicitly.

Before implementing:
- State assumptions clearly. If uncertain, ask.
- If multiple interpretations exist, present them—don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing and ask.

### 2. Simplicity First

Minimum code that solves the problem. Nothing speculative.

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.
- **Test:** Would a senior engineer say this is overcomplicated? If yes, simplify.

### 3. Surgical Changes

Touch only what you must. Clean up only your own mess.

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if different approach preferred.
- If you notice unrelated dead code, mention it—don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that **your** changes made unused.
- Don't remove pre-existing dead code unless asked.

**Test:** Every changed line traces directly to the user's request.

### 4. Goal-Driven Execution

Define success criteria. Loop until verified.

Transform tasks into verifiable goals:
- "Add validation" → Write tests for invalid inputs, then make them pass
- "Fix the bug" → Write a test that reproduces it, then make it pass
- "Refactor X" → Ensure tests pass before and after

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria enable independent looping. Weak criteria ("make it work") require constant clarification.

## Testing Strategy

- **RSpec** for unit and integration tests
- **Factory Bot** for test data
- **WebMock + VCR** for stubbing provider APIs
- **Pundit matchers** for authorization testing
- **Shoulda matchers** for model validations

Every service should have corresponding test exercising Result pattern (success and failure paths).