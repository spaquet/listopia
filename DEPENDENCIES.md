# Listopia Dependencies

Overview of all dependencies used in the Listopia.

## Ruby Gems

### Core Framework
- **rails** (~> 8.1.0) - Ruby on Rails framework
- **pg** (~> 1.6) - PostgreSQL database adapter
- **puma** (>= 5.0) - Web server
- **bootsnap** - Boot time optimization
- **propshaft** - Modern asset pipeline

### Frontend Integration
- **jsbundling-rails** - JavaScript bundling
- **cssbundling-rails** - CSS bundling
- **stimulus-rails** - Stimulus framework integration
- **turbo-rails** - Turbo framework integration
- **jbuilder** - JSON API builder

### Solid Stack (Rails 8 Defaults)
- **solid_cache** - Database-backed cache
- **solid_queue** - Database-backed job queue
- **solid_cable** - Database-backed WebSockets

### Authentication & Authorization
- **bcrypt** (~> 3.1.7) - Password hashing
- **pundit** - Authorization library
- **rolify** - Role management

### Application Features
- **pagy** - Pagination
- **pg_search** - PostgreSQL full-text search
- **noticed** - Notification system
- **positioning** - Ordering/positioning for records
- **logidze** - Audit and version tracking
- **discard** - Soft deletes
- **ruby_llm** - LLM integration
- **multi_json** - JSON processing

### Development Tools
- **debug** - Debugger
- **brakeman** - Security scanning
- **rubocop-rails-omakase** - Ruby style enforcement
- **letter_opener** - Email preview
- **annotaterb** - Model annotations
- **bullet** - N+1 query detection
- **dotenv-rails** - Environment variables

### Testing
- **rspec-rails** - Testing framework
- **factory_bot_rails** - Test fixtures
- **faker** - Fake data generation
- **capybara** - Integration testing
- **selenium-webdriver** - Browser automation
- **database_cleaner-active_record** - Test database cleanup
- **rails-controller-testing** - Controller testing helpers
- **shoulda-matchers** - RSpec matchers
- **rspec-retry** - Retry flaky tests

### Deployment & Performance
- **kamal** - Docker deployment
- **thruster** - HTTP caching and compression for Puma
- **tzinfo-data** - Timezone data

## JavaScript Dependencies

### Package Manager
- **Bun** - JavaScript package manager and runtime

### Core Libraries
- **@hotwired/stimulus** (^3.2.2) - Stimulus framework
- **@hotwired/turbo-rails** (^8.0.20) - Turbo framework

### CSS
- **tailwindcss** (^4.1.16) - Utility-first CSS framework
- **@tailwindcss/cli** (^4.1.16) - Tailwind CLI

### UI Components
- **sortablejs** (^1.15.6) - Drag and drop library
- **@stimulus-components/character-counter** (^5.1.0) - Character counter
- **@stimulus-components/notification** (^3.0.0) - Notifications
- **@stimulus-components/reveal** (^5.0.0) - Reveal/hide toggle
- **@stimulus-components/scroll-to** (^5.0.1) - Scroll behavior
- **stimulus-textarea-autogrow** (^4.1.0) - Auto-growing textarea

### Utilities
- **marked** (^16.4.1) - Markdown parser
- **highlight.js** (^11.11.1) - Code syntax highlighting
- **lodash** (^4.17.21) - Utility library