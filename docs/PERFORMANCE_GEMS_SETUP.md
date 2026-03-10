# Performance Analysis Gems - Setup Guide (Rails 8.1)

## Overview

This guide covers gems for database N+1 analysis and performance profiling. You already have `bullet` (8.1.0) and `rack-mini-profiler` (4.0.1) ✅. I've updated recommendations to use only actively maintained gems for Rails 8.1.

---

## Recommended Gems (Updated for Rails 8.1)

### 1. **Bullet** ✅ Already Installed
**Purpose**: Detects N+1 queries and unused eager loading

**Status**: Actively maintained, Rails 8.1 compatible (v8.1.0)
**Your version**: 8.1.0

Just ensure it's enabled in development:

```ruby
# config/environments/development.rb
if defined?(Bullet)
  Bullet.enable = true
  Bullet.alert = false
  Bullet.bullet_logger = true
  Bullet.rails_logger = true
  Bullet.console = true
  Bullet.add_footer = true
end
```

---

### 2. **Rack Mini Profiler** ✅ Already Installed
**Purpose**: Live request profiling with SQL query analysis in the browser

**Status**: Actively maintained, Rails 8.1 compatible (v4.0.1)
**Your version**: 4.0.1

Already configured. Just enable caching for faster development:

```ruby
# config/environments/development.rb
if defined?(Rack::MiniProfiler)
  Rack::MiniProfiler.config.enable_caching = true
  Rack::MiniProfiler.config.backtrace_includes = /listopia|app/
  Rack::MiniProfiler.config.max_data_length = 10000
  Rack::MiniProfiler.config.flamegraph_mode = :objspace
end
```

**Usage**:
```bash
rails s
# Visit http://localhost:3000
# Click the speed badge (top-left) to see query analysis
```

**What you'll see**:
- Total request time breakdown
- SQL query count and time
- Query durations ranked
- Memory usage
- Flamegraph visualization

---

### 3. **Memory Profiler** (NEW - Actively Maintained)

**Purpose**: Analyze memory usage - identify memory leaks and large allocations

**Installation**:
```ruby
# Gemfile - development group
gem "memory_profiler"
```

**Rails 8.1 Status**: ✅ Fully compatible

**Usage** - In Rails console:

```ruby
require 'memory_profiler'

report = MemoryProfiler.report do
  # Your slow code here
  List.includes(:owner, :collaborators).limit(100).each do |list|
    list.list_items.count
  end
end

report.pretty_print
```

**Output**:
```
Total allocated: 2.5 MB (50,000 objects)
Total retained: 1.2 MB (10,000 objects)

Top 10 allocations:
  1. String        1.2 MB (15,000 allocations)
  2. Array         0.8 MB (8,000 allocations)
  3. Hash          0.5 MB (2,000 allocations)
```

**Use case**: Find which objects are growing unbounded in loops

---

### 4. **Stackprof** (CPU Profiling - Actively Maintained)

**Purpose**: CPU sampling profiler - identifies slow Ruby code

**Installation**:
```ruby
# Gemfile - development group
gem "stackprof"
```

**Rails 8.1 Status**: ✅ Fully compatible

**Usage** - In Rails console:

```ruby
require 'stackprof'

# Profile CPU usage
report = StackProf.run(mode: :cpu, raw: true) do
  # Your slow code
  10.times do
    List.includes(:owner, :collaborators).limit(50).each do |list|
      list.list_items.count
    end
  end
end

# Print results
StackProf.results(report, :text)
```

**Output**:
```
Samples  %Self  %Total  Method
  5000   20.0%   40.0%  Array#each
  3000   12.0%   32.0%  List#collaborators
  2000    8.0%   16.0%  ListItem.count
```

---

### 5. **Prosopite** (Modern N+1 Alternative)

**Purpose**: Alternate N+1 detector - can catch some cases Bullet misses

**Installation**:
```ruby
# Gemfile - development group
gem "prosopite"
```

**Rails 8.1 Status**: ✅ Actively maintained, Rails 8.1 compatible

**Why optional**: You already have Bullet, but Prosopite is good for:
- Different detection algorithm (catches edge cases)
- JSON output (easier CI integration)
- Thread-safe (better for concurrent testing)

**Configuration** - `config/initializers/prosopite.rb`:

```ruby
Prosopite.tap do |prosopite|
  prosopite.enabled = Rails.env.development?
  prosopite.stderr = true      # Log to STDERR
  prosopite.raise = false      # Don't raise in dev (annoying)
  prosopite.notify = true      # Show notifications
  prosopite.auto_explain = true
end
```

---

### 6. **RuboCop Performance Cops** (Already Mostly Installed)

**Purpose**: Static code analysis for performance anti-patterns

**Status**: You have `rubocop-rails-omakase` ✅ which includes performance cops

**Check what's enabled**:
```bash
bundle exec rubocop --show-cops | grep Performance
```

**Usage**:
```bash
# Run all cops (including performance)
bundle exec rubocop

# Run performance cops only
bundle exec rubocop -D | grep Performance
```

**What it catches**:
```ruby
# ❌ Slow: Creates array just to check membership
if ["draft", "active"].include?(list.status)

# ✅ Fast: Use constant
VALID_STATUSES = ["draft", "active"]
if VALID_STATUSES.include?(list.status)

# ❌ Slow: N+1 in string interpolation
users.each { |u| "User: #{u.posts.count}" }

# ✅ Fast: Eager load first
users.includes(:posts).each { |u| "User: #{u.posts.size}" }
```

---

## Setup Steps (Rails 8.1)

### Step 1: Add New Gems to Gemfile

```ruby
# Gemfile
group :development do
  gem "bullet"  # Already have (v8.1.0) ✅
  gem "rack-mini-profiler"  # Already have (v4.0.1) ✅

  # ADD THESE (actively maintained for Rails 8.1):
  gem "memory_profiler"    # Memory analysis
  gem "stackprof"          # CPU profiling
  gem "prosopite"          # Alternative N+1 detector (optional)

  # RuboCop with performance cops (already have rubocop-rails-omakase)
  # gem "rubocop-performance"  # Part of omakase, no need to add
end
```

### Step 2: Install

```bash
bundle install
```

### Step 3: Configure Initializers

**Option A: Minimal Setup** (Recommended - just enable defaults)

Most configuration is automatic in development. Just enable in `config/environments/development.rb`:

```ruby
# config/environments/development.rb
# Bullet is auto-enabled with sensible defaults
if defined?(Bullet)
  Bullet.enable = true
  Bullet.alert = false
  Bullet.rails_logger = true
  Bullet.console = true
end

# Rack Mini Profiler works out of the box
if defined?(Rack::MiniProfiler)
  Rack::MiniProfiler.config.enable_caching = true
end
```

**Option B: Full Configuration** (Advanced)

Create `config/initializers/performance.rb`:

```ruby
# config/initializers/performance.rb

# Bullet - N+1 detection
if defined?(Bullet) && Rails.env.development?
  Bullet.enable = true
  Bullet.alert = false
  Bullet.bullet_logger = true
  Bullet.rails_logger = true
  Bullet.console = true
  Bullet.add_footer = true
  Bullet.skip_html_injection = false
  Bullet.stacktrace_excludes = [ %r{gems/rails}, %r{gems/bundler} ]
end

# Rack Mini Profiler - live request profiling
if defined?(Rack::MiniProfiler) && Rails.env.development?
  Rack::MiniProfiler.config.enable_caching = true
  Rack::MiniProfiler.config.backtrace_includes = /listopia|app/
  Rack::MiniProfiler.config.max_data_length = 10000
  Rack::MiniProfiler.config.flamegraph_mode = :objspace
  Rack::MiniProfiler.config.show_total_sql_time = true
end

# Prosopite - Alternative N+1 detector (if you add the gem)
if defined?(Prosopite) && Rails.env.development?
  Prosopite.tap do |prosopite|
    prosopite.enabled = true
    prosopite.stderr = true
    prosopite.raise = false
    prosopite.notify = true
  end
end
```

---

## Usage Workflows

### Workflow 1: Find N+1 Queries (Bullet) ⭐ Start Here

```bash
rails s
# Open browser to http://localhost:3000/lists
# Check browser console for Bullet notifications:
#
# ⚠️ N+1 Query detected:
#   User => [:posts]
#   Call stack from /app/controllers/lists_controller.rb:42
#   Add to your query: .includes(:posts)
```

**Also check Rails server logs for detailed output:**
```
SELECT "users".* FROM "users" WHERE "id" = $1  [0.2ms]
SELECT "users".* FROM "users" WHERE "id" = $2  [0.1ms]
SELECT "users".* FROM "users" WHERE "id" = $3  [0.1ms]
⚠️ N+1 Query detected: User => [:posts]
```

---

### Workflow 2: Profile Request Time (Rack Mini Profiler)

This is the **fastest way to identify slow pages**:

```bash
rails s
# Visit http://localhost:3000
# See speed badge in top-left corner: "10ms" or "50ms"
# Click it to see:
#   - Request timeline
#   - SQL queries and time
#   - Slowest queries highlighted
#   - Memory usage
#   - Flamegraph (visual breakdown)
```

**Most useful for:**
- Comparing request times before/after fixes
- Identifying which page is slowest
- Seeing real database time

---

### Workflow 3: Analyze Memory Usage (Memory Profiler)

**Find memory leaks or large allocations:**

```bash
rails c

require 'memory_profiler'

report = MemoryProfiler.report do
  # Your problematic code:
  100.times do
    List.all.each { |list| list.collaborators.count }
  end
end

report.pretty_print(retained: 10)
```

**Output shows:**
- Where memory is being allocated
- Which objects are holding references
- Useful for loop-based memory leaks

---

### Workflow 4: Profile CPU Performance (StackProf)

**Find non-database slowness:**

```bash
rails c

require 'stackprof'

result = StackProf.run(mode: :cpu, raw: true, limit: 100) do
  # Your slow code here
  10.times do
    Chat.includes(:messages, :user).limit(100).each do |chat|
      chat.messages.each { |m| m.user.name }
    end
  end
end

StackProf.results(result, :text)
```

**Use when:**
- Request time is slow but SQL queries look fast
- You suspect Ruby code (not database) is bottleneck
- Parsing/JSON/large loops are slow

---

### Workflow 5: Static Code Analysis (RuboCop)

**Find obvious performance anti-patterns:**

```bash
# Run RuboCop with performance focus
bundle exec rubocop -D app/ | grep Performance

# Or just run normal rubocop (includes performance)
bundle exec rubocop app/
```

**Catches things like:**
```ruby
# ❌ Flagged: count > 0 is slower
if list.items.count > 0

# ✅ Suggested: Use any? instead
if list.items.any?
```

---

### Workflow 6: Cross-Check with Prosopite (Optional)

If you added Prosopite gem, it runs in background:

```
# In Rails console or server logs, you'll see:
Prosopite detected N+1 query: Chat has_many messages
  Location: app/services/chat_completion_service.rb:42
```

**Use when:**
- Bullet misses something
- Need JSON output for CI/CD
- Testing in multithreaded environment

---

## Key Metrics to Monitor

### From Bullet (N+1 Detection)

```
GOOD: 0 warnings
⚠️ ACCEPTABLE: < 3 warnings per page
❌ BAD: > 5 warnings per page
```

### From Rack Mini Profiler

Look for:
```
Query time:
  < 100ms    ✅ Good
  100-500ms  ⚠️ Investigate
  > 500ms    ❌ Critical
```

### From Rack Mini Profiler (Query Times)

Look at slowest queries:
```
SELECT "lists".* ... [45ms] ⚠️ Slow, needs optimization
SELECT "users".* ... [2ms] ✅ Fast
```

---

## Common N+1 Patterns & Fixes

### Pattern 1: Accessing Association in Loop

```ruby
# ❌ BAD - N+1 queries (1 + N)
lists = List.all
lists.each do |list|
  puts list.owner.name  # Query per list!
end

# ✅ GOOD - Single query
lists = List.includes(:owner)
lists.each do |list|
  puts list.owner.name
end

# ✅ BETTER - If you only need names
owners = List.joins(:owner).select("lists.*, users.name")
```

### Pattern 2: Counting in Loop

```ruby
# ❌ BAD - N+1 COUNT queries
lists = List.all
lists.each do |list|
  puts list.list_items.count  # COUNT query per list!
end

# ✅ GOOD - Single COUNT query with eager loading
lists = List.includes(:list_items)
lists.each do |list|
  puts list.list_items.size  # Uses loaded association (no query)
end

# ✅ BEST - Counter cache (no query at all)
# After migration, use:
lists = List.all
lists.each do |list|
  puts list.items_count  # Direct column read
end
```

### Pattern 3: Conditional Association Loading

```ruby
# ❌ BAD - May load some but miss others
lists = List.all.limit(10)
lists.each do |list|
  if list.collaborators.any?  # Query if not loaded!
    puts "Has collaborators"
  end
end

# ✅ GOOD - Always eager load
lists = List.includes(:collaborators).limit(10)
lists.each do |list|
  if list.collaborators.any?  # Uses loaded association
    puts "Has collaborators"
  end
end
```

### Pattern 4: Method Call on Association

```ruby
# ❌ BAD - Query per chat
chats = Chat.all
chats.each do |chat|
  puts chat.messages.recent.first.content  # Loads messages per chat!
end

# ✅ GOOD - Eager load with scope
chats = Chat.includes(:messages)
chats.each do |chat|
  puts chat.messages.recent.first.content
end

# ✅ BETTER - Use join if you just need specific data
Message.joins(:chat).where(chat_id: chat_ids).recent
```

---

## Performance Testing Checklist

- [ ] Run `bundle add memory_profiler stackprof --group development`
- [ ] Configure `config/initializers/performance.rb` (optional but recommended)
- [ ] Start `rails s` and visit http://localhost:3000
- [ ] Check Bullet warnings in browser console
- [ ] Click speed badge for Rack Mini Profiler details
- [ ] Note current page load time (e.g., "50ms")
- [ ] Run `bundle exec rubocop app/ | grep Performance`
- [ ] Implement 3-5 quick N+1 fixes (see Common N+1 Patterns)
- [ ] Measure improvement (target: < 20ms for /lists page)
- [ ] Document fixes in git commits
- [ ] Update CLAUDE.md with new performance patterns

---

## Production Considerations

### Gem Groups Automatically Limit to Development

All profiling gems in `:development` group are **never loaded in production** 🔒

```ruby
# Gemfile
group :development do
  gem "bullet"            # Development only ✅
  gem "rack-mini-profiler"  # Development only ✅
  gem "memory_profiler"   # Development only ✅
  gem "stackprof"         # Development only ✅
  gem "prosopite"         # Development only ✅
end

# Production is unaffected!
```

### Optional: Production APM (Application Performance Monitoring)

To monitor performance in production, add to `Gemfile`:

```ruby
group :production do
  # Option 1: New Relic (most popular)
  gem "newrelic_rpm"

  # Option 2: Scout APM
  gem "scout_apm"

  # Option 3: Skylight
  gem "skylight"

  # Option 4: Datadog
  gem "datadog"
end
```

**Recommendation**: Add NewRelic free tier to catch real-world issues that don't appear in development.

---

## Troubleshooting

### Rack Mini Profiler Not Showing

```bash
# Make sure it's not in a conditional require
# Check Gemfile line:
gem "rack-mini-profiler", require: false  # This is correct

# Then in code, it loads automatically in development
```

### Query Tracer Too Verbose

```ruby
# In config/initializers/performance.rb
config.backtrace_excludes = /gems|bundles|node_modules/
# Add more paths to exclude noise
```

### Bullet False Positives

```ruby
# Sometimes Bullet flags things that aren't real N+1s
# Suppress with:
Bullet.add_safelist type: :n_plus_one_query,
                    class_name: "Chat",
                    association: :messages
```

---

## Quick Start

Fastest way to get started (5 minutes):

```bash
# 1. Add gems (only actively maintained for Rails 8.1)
bundle add memory_profiler stackprof --group development

# 2. Start server
rails s

# 3. Visit http://localhost:3000
#    - Check browser for Bullet notifications (top-left area)
#    - Click speed badge (top-left) for Rack Mini Profiler

# 4. Check Rails server console for N+1 warnings

# 5. Run RuboCop for code analysis
bundle exec rubocop app/

# Done! You now have 3 tools actively monitoring performance:
#   ✅ Bullet - N+1 detection (automatic)
#   ✅ Rack Mini Profiler - Request profiling (automatic)
#   ✅ Memory Profiler - Memory analysis (on-demand)
#   ✅ StackProf - CPU profiling (on-demand)
#   ✅ RuboCop - Code anti-patterns (automatic)
```

**Next steps:**
1. Note the current speed badge time (e.g., "50ms")
2. Implement fixes from N+1 section
3. Measure improvement (target: < 20ms)
4. Fix the top 5 slowest queries first

That's it! Start identifying and fixing issues based on the reports.
