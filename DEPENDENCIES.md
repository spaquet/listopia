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
- **friendly_id** - Human-readable slugs for URLs
- **acts-as-taggable-on** - Tag support for models
- **image_processing** (~> 1.2) - Image variants and transformations

### AI & Search Features
- **ruby_llm** (~> 1.8+) - LLM integration for AI-powered chat, intent detection, and embeddings
- **neighbor** - Vector similarity search for semantic embeddings (pgvector integration)
- **multi_json** - JSON processing for MCP and API responses

### Markdown & Content Rendering
- **redcarpet** - Markdown rendering for rich text
- **rouge** - Code syntax highlighting in markdown

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
- **cuprite** - Headless browser testing
- **vcr** (~> 6.2) - HTTP request recording and playback
- **webmock** (~> 3.18) - HTTP mocking for tests
- **database_cleaner-active_record** - Test database cleanup
- **rails-controller-testing** - Controller testing helpers
- **shoulda-matchers** (~> 7.0) - RSpec matchers for model testing
- **rspec-retry** - Retry flaky tests
- **timecop** - Time-based testing utilities

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
- **tailwindcss** (^4.1.17) - Utility-first CSS framework (upgraded from 4.1.16)
- **@tailwindcss/cli** (^4.1.17) - Tailwind CLI (upgraded from 4.1.16)

### UI Components & Interactions
- **sortablejs** (^1.15.6) - Drag and drop library
- **@stimulus-components/character-counter** (^5.1.0) - Character counter
- **@stimulus-components/notification** (^3.0.0) - Notifications
- **@stimulus-components/reveal** (^5.0.0) - Reveal/hide toggle
- **@stimulus-components/scroll-to** (^5.0.1) - Scroll behavior
- **stimulus-textarea-autogrow** (^4.1.0) - Auto-growing textarea

### Rich Text Editor
- **prosemirror-model** (^1.25.4) - ProseMirror document model
- **prosemirror-state** (^1.4.4) - Editor state management
- **prosemirror-view** (^1.41.4) - Editor view and DOM binding
- **prosemirror-transform** (^1.10.5) - Document transformations
- **prosemirror-commands** (^1.7.1) - Editor commands
- **prosemirror-keymap** (^1.2.3) - Keyboard handling
- **prosemirror-schema-list** (^1.5.1) - List schema support
- **prosemirror-markdown** (^1.13.2) - Markdown serialization

### Utilities
- **marked** (^17.0.1) - Markdown parser (upgraded from 16.4.1)
- **highlight.js** (^11.11.1) - Code syntax highlighting
- **lodash** (^4.17.21) - Utility library

---

## Recent Additions & Upgrades

### New Gems (Recently Added)

**AI & Search:**
- `neighbor` - Vector similarity search for pgvector embeddings
- `redcarpet` - Markdown rendering for rich text content
- `rouge` - Code syntax highlighting in markdown

**Database & Content:**
- `friendly_id` - Human-readable URL slugs
- `image_processing` - Image variants and transformations

**Testing:**
- `cuprite` - Headless browser testing
- `vcr` - HTTP request recording/playback for tests
- `webmock` - HTTP mocking for tests
- `timecop` - Time-based testing utilities

### Upgraded Dependencies

**Ruby Gems:**
- `ruby_llm` → 1.8+ (Enhanced LLM integration with embeddings)
- `shoulda-matchers` → 7.0 (Better model testing)

**JavaScript:**
- `tailwindcss` → 4.1.17 (from 4.1.16)
- `@tailwindcss/cli` → 4.1.17 (from 4.1.16)
- `marked` → 17.0.1 (from 16.4.1)

### New Feature Support

**AI-Powered Chat:**
- Integrated `ruby_llm` 1.8+ for intent detection, embeddings, and LLM calls
- Added `neighbor` for vector similarity in semantic search
- Full RAG (Retrieval-Augmented Generation) support

**Rich Text & Content:**
- `ProseMirror` libraries for advanced rich text editing
- `redcarpet` + `rouge` for beautiful markdown rendering
- `image_processing` for image variants and optimization

**Testing Infrastructure:**
- `cuprite` for headless browser automation
- `vcr` + `webmock` for API testing (especially for LLM mocks)
- `timecop` for time-dependent feature testing

---

## Dependency Statistics

- **Total Ruby Gems:** 50+
- **Total JavaScript Dependencies:** 20+
- **Testing Libraries:** 13 (comprehensive test suite support)
- **AI/ML Libraries:** 2 (RubyLLM, Neighbor)
- **UI Framework Libraries:** 3 (Stimulus, Turbo, Tailwind)

## Notes

- All gems are pinned or ranged versions for stability
- Development/test gems are properly grouped
- pgvector PostgreSQL extension required for semantic search (via `neighbor` gem)
- Bun is the preferred package manager (faster than npm/yarn)
