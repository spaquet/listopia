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
- **ruby_llm-schema** - Structured output support with schemas
- **neighbor** - Vector similarity search for semantic embeddings (pgvector integration)
- **multi_json** - JSON processing for MCP and API responses
- **jwt** - JWT token handling for OAuth

### Markdown & Content Rendering
- **redcarpet** - Markdown rendering for rich text
- **rouge** - Code syntax highlighting in markdown
- **csv** - CSV processing (required for Ruby 3.4+)

### Development Tools
- **debug** - Debugger
- **brakeman** - Security scanning
- **rubocop-rails-omakase** - Ruby style enforcement
- **letter_opener** - Email preview
- **annotaterb** - Model annotations
- **bullet** - N+1 query detection
- **dotenv-rails** - Environment variables
- **rack-mini-profiler** - Performance profiling and insights
- **stackprof** - Sampling CPU profiler for bottleneck identification
- **prosopite** - Object allocation and memory tracking
- **memory_profiler** - Detailed memory usage reports

### Testing
- **rspec-rails** - Testing framework
- **factory_bot_rails** - Test fixtures
- **faker** - Fake data generation
- **capybara** - Integration testing
- **selenium-webdriver** - Browser automation
- **cuprite** - Headless browser testing
- **vcr** (~> 6.2) - HTTP request recording and playback
- **webmock** (~> 3.18) - HTTP mocking for tests
- **simplecov** (~> 0.22.0) - Code coverage reporting
- **database_cleaner-active_record** - Test database cleanup
- **rails-controller-testing** - Controller testing helpers
- **shoulda-matchers** (~> 7.0) - RSpec matchers for model testing
- **pundit-matchers** (~> 4.0.0) - Pundit authorization testing
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
- **@hotwired/turbo-rails** (^8.0.23) - Turbo framework

### CSS
- **tailwindcss** (^4.2.4) - Utility-first CSS framework
- **@tailwindcss/cli** (^4.2.4) - Tailwind CLI

### UI Components & Interactions
- **sortablejs** (^1.15.7) - Drag and drop library
- **@stimulus-components/character-counter** (^5.1.0) - Character counter
- **@stimulus-components/notification** (^3.0.0) - Notifications
- **@stimulus-components/reveal** (^5.0.0) - Reveal/hide toggle
- **@stimulus-components/scroll-to** (^5.0.1) - Scroll behavior
- **stimulus-textarea-autogrow** (^4.1.0) - Auto-growing textarea

### Utilities
- **marked** (^17.0.6) - Markdown parser
- **highlight.js** (^11.11.1) - Code syntax highlighting

---

## Recent Additions & Upgrades

### New Gems (Recently Added)

**AI & Search:**
- `ruby_llm-schema` - Structured output with schemas for LLM responses
- `jwt` - JWT token handling for OAuth

**Development Tools:**
- `rack-mini-profiler` - HTTP request profiling and caching analysis
- `stackprof` - Sampling-based CPU profiler for bottleneck identification
- `prosopite` - Object allocation and memory leak detection
- `memory_profiler` - Detailed memory usage analysis

**Testing:**
- `simplecov` - Code coverage reporting
- `pundit-matchers` - Pundit authorization policy matchers

### Upgraded Dependencies

**Ruby Gems:**
- `ruby_llm` → 1.8+ (Enhanced LLM integration with embeddings)
- `shoulda-matchers` → 7.0 (Better model testing)
- `solid_queue` → async-worker-execution-mode branch (Fiber-based async execution)

**JavaScript:**
- `@hotwired/turbo-rails` → 8.0.23 (from 8.0.20)
- `tailwindcss` → 4.2.4 (from 4.1.17)
- `@tailwindcss/cli` → 4.2.4 (from 4.1.17)
- `marked` → 17.0.6 (from 17.0.1)
- `sortablejs` → 1.15.7 (from 1.15.6)

### New Feature Support

**AI-Powered Chat:**
- Integrated `ruby_llm` 1.8+ with `ruby_llm-schema` for structured output
- LLM intent detection, embeddings, and schema validation
- `neighbor` for vector similarity in semantic search
- Full RAG (Retrieval-Augmented Generation) support

**Rich Text & Content:**
- `redcarpet` + `rouge` for beautiful markdown rendering with syntax highlighting
- `image_processing` for image variants and optimization
- `friendly_id` for human-readable URL slugs

**Performance & Profiling:**
- `rack-mini-profiler` for HTTP request analysis
- `stackprof`, `prosopite`, `memory_profiler` for bottleneck identification
- `bullet` for N+1 query detection and prevention

**Testing Infrastructure:**
- `cuprite` for headless browser automation
- `vcr` + `webmock` for API testing (especially for LLM mocks)
- `timecop` for time-dependent feature testing
- `simplecov` for code coverage reporting
- `pundit-matchers` for authorization testing

---

## Dependency Statistics

- **Total Ruby Gems:** 55+
- **Total JavaScript Dependencies:** 11
- **Testing Libraries:** 15 (comprehensive test suite support)
- **Performance Profiling:** 4 (rack-mini-profiler, stackprof, prosopite, memory_profiler)
- **AI/ML Libraries:** 3 (RubyLLM, RubyLLM-Schema, Neighbor)
- **UI Framework Libraries:** 3 (Stimulus, Turbo, Tailwind)

## Notes

- All gems are pinned or ranged versions for stability
- Development/test gems are properly grouped
- pgvector PostgreSQL extension required for semantic search (via `neighbor` gem)
- Bun is the preferred package manager (faster than npm/yarn)
- `solid_queue` uses async-worker-execution-mode branch for Fiber-based async execution
- Performance profiling tools (rack-mini-profiler, stackprof, prosopite) enabled for development
- `ruby_llm-schema` provides structured output validation for LLM responses
