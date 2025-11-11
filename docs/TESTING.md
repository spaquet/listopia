# Testing

Listopia uses **RSpec** as the sole testing framework with a phased, pyramid-based approach. Tests are organized by layer, ensuring comprehensive coverage while maintaining fast feedback cycles.

## Overview

The testing pyramid for Listopia consists of **four layers**, each serving a specific purpose:

```
        System Tests (Full workflows)
      /         Browser automation       \
    /          End-to-end validation      \
  /_____________________________________ \
           Integration Tests
         (Services, jobs, policies)
      Policy tests, notification tests,
       background job integration
  ___________________________________
          Controller Tests
    Authorization, responses, formats
  ___________________________________
      Unit Tests (Model Tests)
   Validations, associations, methods
```

Each layer **only tests what it's responsible for**, avoiding redundant test coverage and keeping the test suite fast.

## Test Stack

- **[RSpec Rails](https://github.com/rspec/rspec-rails)** - Behavior-driven testing framework
- **[Factory Bot](https://github.com/thoughtbot/factory_bot)** - Test data generation
- **[Faker](https://github.com/faker-ruby/faker)** - Realistic fake data
- **[Capybara](https://github.com/teamcapybara/capybara)** - Browser interaction testing
- **[Cuprite](https://github.com/rubycdp/cuprite)** - Headless Chrome driver (recommended over Selenium)
- **[Database Cleaner](https://github.com/DatabaseCleaner/database_cleaner)** - Test database cleanup
- **[Shoulda Matchers](https://github.com/thoughtbot/shoulda-matchers)** - Concise model matchers
- **[RSpec Retry](https://github.com/NoRedInk/rspec-retry)** - Flaky test retry handling
- **[Timecop](https://github.com/travisci/timecop)** - Time freezing for time-dependent tests

## Production-Ready Test Suite

Listopia uses a **phased testing approach** where only fully-tested, production-ready models are run in the deployment pipeline. This allows the test suite to grow incrementally while maintaining deployment reliability.

### Currently Production-Ready Models

The following models have complete, reliable test coverage across all layers and are automatically tested on every deployment:

- **User** - Authentication, validation, associations, and security
- **Invitation** - Invitation creation, token generation, acceptance, and authorization
- **Session** - Session management, token handling, and authentication state

### Running Production-Ready Tests

Use the Rake task to run only production-ready tests locally:

```bash
bundle exec rails test:production_ready
```

Or run specific production-ready models:

```bash
bundle exec rspec spec/models/user_spec.rb
bundle exec rspec spec/models/invitation_spec.rb
bundle exec rspec spec/models/session_spec.rb
```

### Continuous Integration

Every push to `main` and every pull request automatically runs the production-ready test suite via GitHub Actions. This ensures only proven code reaches production.

Check `.github/workflows/ci.yml` for CI configuration.

## Test Directory Structure

```
spec/
├── models/                        # Layer 1: Unit tests
│   ├── user_spec.rb              # ✅ Production-ready
│   ├── invitation_spec.rb        # ✅ Production-ready
│   ├── session_spec.rb           # ✅ Production-ready
│   ├── list_spec.rb              # 🚧 In progress
│   ├── list_item_spec.rb         # 🚧 In progress
│   └── comment_spec.rb           # 🚧 In progress
├── policies/                      # Layer 2: Authorization tests
│   ├── list_policy_spec.rb
│   ├── list_item_policy_spec.rb
│   └── comment_policy_spec.rb
├── services/                      # Layer 2: Service & business logic tests
│   ├── list_sharing_service_spec.rb
│   └── comment_service_spec.rb
├── controllers/                   # Layer 3: Integration tests (HTTP layer)
│   ├── lists_controller_spec.rb
│   ├── list_items_controller_spec.rb
│   └── comments_controller_spec.rb
├── requests/                      # Layer 3: API/request specs (alternative to controllers)
│   └── lists_api_spec.rb
├── system/                        # Layer 4: End-to-end tests (browser)
│   ├── authentication_spec.rb
│   ├── list_management_spec.rb
│   ├── real_time_collaboration_spec.rb
│   └── comment_workflows_spec.rb
├── factories/                     # Test data builders
│   ├── users.rb
│   ├── lists.rb
│   ├── list_items.rb
│   ├── comments.rb
│   └── invitations.rb
├── support/                       # RSpec configuration & helpers
│   ├── authentication_helpers.rb
│   ├── capybara_helpers.rb
│   ├── database_cleaner.rb
│   ├── capybara.rb
│   └── rspec_config.rb
└── rails_helper.rb               # Main RSpec configuration
```

## Testing Strategy by Layer

### Layer 1: Model Tests (Unit Tests)

**Purpose:** Test validations, associations, and business logic in isolation.

**What to test:**
- Validations (presence, length, uniqueness, format)
- Associations (has_many, belongs_to, polymorphic)
- Instance methods (custom business logic)
- Scopes (query methods)
- Enums (status transitions, constraints)

**What NOT to test:**
- Rails framework code
- External service calls (mock these)
- Database persistence (that's Rails' job)
- View rendering
- Controller logic

**Example:**

```ruby
# spec/models/list_spec.rb
RSpec.describe List, type: :model do
  describe "associations" do
    it { should belong_to(:owner).class_name("User") }
    it { should have_many(:list_items).dependent(:destroy) }
    it { should have_many(:collaborators).through(:list_collaborations) }
    it { should have_many(:comments).dependent(:destroy) }
  end

  describe "validations" do
    it { should validate_presence_of(:title) }
    it { should validate_length_of(:title).is_at_most(255) }
    it { should validate_inclusion_of(:status).in_array(["draft", "active", "completed", "archived"]) }
  end

  describe "#completion_percentage" do
    let(:list) { create(:list) }

    it "returns 0 for empty list" do
      expect(list.completion_percentage).to eq(0)
    end

    it "calculates percentage correctly" do
      create_list(:list_item, 3, list: list, status: :completed)
      create_list(:list_item, 2, list: list, status: :pending)
      
      expect(list.completion_percentage).to eq(60.0)
    end
  end

  describe "#readable_by?" do
    let(:owner) { create(:user) }
    let(:collaborator) { create(:user) }
    let(:other_user) { create(:user) }
    let(:list) { create(:list, owner: owner) }

    it "is readable by owner" do
      expect(list.readable_by?(owner)).to be_truthy
    end

    it "is readable by collaborator" do
      list.collaborators.create!(user: collaborator, permission: :view)
      expect(list.readable_by?(collaborator)).to be_truthy
    end

    it "is not readable by other users" do
      expect(list.readable_by?(other_user)).to be_falsy
    end

    it "is readable by anyone if public" do
      list.update!(is_public: true)
      expect(list.readable_by?(other_user)).to be_truthy
    end
  end

  describe "broadcasting" do
    it "broadcasts when list is updated" do
      list = create(:list)
      
      expect {
        list.update!(title: "Updated Title")
      }.to have_broadcasted_to("list_#{list.id}")
    end
  end
end
```

### Layer 2: Policy & Service Tests (Integration Tests)

**Purpose:** Test authorization rules and business logic that spans multiple models or involves external dependencies.

#### Policy Tests

Test Pundit authorization policies independently from controllers:

```ruby
# spec/policies/list_policy_spec.rb
RSpec.describe ListPolicy do
  let(:user) { create(:user) }
  let(:owner) { create(:user) }
  let(:other_user) { create(:user) }
  let(:list) { create(:list, owner: owner) }

  describe "#show?" do
    it "allows owner to show their list" do
      expect(ListPolicy.new(owner, list)).to permit(:show)
    end

    it "allows collaborators with view permission to show" do
      list.collaborators.create!(user: user, permission: :view)
      expect(ListPolicy.new(user, list)).to permit(:show)
    end

    it "denies other users" do
      expect(ListPolicy.new(other_user, list)).not_to permit(:show)
    end

    it "allows anyone if list is public" do
      list.update!(is_public: true)
      expect(ListPolicy.new(other_user, list)).to permit(:show)
    end
  end

  describe "#update?" do
    it "allows owner to update" do
      expect(ListPolicy.new(owner, list)).to permit(:update)
    end

    it "allows collaborators with edit permission" do
      list.collaborators.create!(user: user, permission: :edit)
      expect(ListPolicy.new(user, list)).to permit(:update)
    end

    it "denies collaborators with view-only permission" do
      list.collaborators.create!(user: user, permission: :view)
      expect(ListPolicy.new(user, list)).not_to permit(:update)
    end

    it "denies other users" do
      expect(ListPolicy.new(other_user, list)).not_to permit(:update)
    end
  end

  describe "#destroy?" do
    it "allows only the owner to destroy" do
      expect(ListPolicy.new(owner, list)).to permit(:destroy)
      expect(ListPolicy.new(user, list)).not_to permit(:destroy)
    end
  end
end
```

#### Service Tests

Test complex business logic and notifications:

```ruby
# spec/services/comment_service_spec.rb
RSpec.describe CommentService do
  describe "#create" do
    let(:user) { create(:user) }
    let(:list) { create(:list) }
    let(:collaborator) { create(:user) }

    before { list.collaborators.create!(user: collaborator, permission: :comment) }

    it "creates comment with valid params" do
      expect {
        CommentService.new(user, list, content: "Great list!").create
      }.to change(Comment, :count).by(1)
    end

    it "broadcasts to commentable resource" do
      comment = create(:comment, commentable: list, user: user)
      
      expect {
        CommentService.new(user, list, content: "Reply").create
      }.to have_broadcasted_to("list_#{list.id}")
    end

    it "notifies list owner of new comment" do
      expect {
        CommentService.new(user, list, content: "Great!").create
      }.to have_enqueued_job(Noticed::DeliveryJob)
    end

    it "raises error if user cannot comment" do
      other_user = create(:user)
      
      expect {
        CommentService.new(other_user, list, content: "Hack!").create
      }.to raise_error(Pundit::NotAuthorizedError)
    end
  end
end
```

#### Notification & Broadcasting Tests

```ruby
# spec/models/comment_spec.rb or spec/services/notification_spec.rb
RSpec.describe "Comment Notifications" do
  let(:owner) { create(:user) }
  let(:commenter) { create(:user) }
  let(:list) { create(:list, owner: owner) }

  it "notifies list owner when someone comments" do
    expect {
      create(:comment, commentable: list, user: commenter, content: "Nice!")
    }.to have_enqueued_job(Noticed::DeliveryJob)
  end

  it "notifies other commenters of new replies" do
    comment1 = create(:comment, commentable: list, user: create(:user))
    
    expect {
      create(:comment, commentable: list, user: commenter, parent: comment1)
    }.to have_enqueued_job(Noticed::DeliveryJob)
  end

  it "broadcasts comment to subscribers" do
    expect {
      create(:comment, commentable: list, user: commenter)
    }.to have_broadcasted_to("list_#{list.id}")
  end
end
```

### Layer 3: Controller Tests (Integration Tests)

**Purpose:** Test HTTP layer - authorization checks, response formats, and side effects.

**What to test:**
- Authorization (verify `authorize` is called)
- HTTP status codes (success vs. error)
- Response format (HTML, JSON, Turbo Stream)
- Instance variable assignments
- Redirects and error handling

**What NOT to test:**
- Business logic (tested in models)
- Authorization rules (tested in policies)
- Full workflows (tested in system specs)

**Example:**

```ruby
# spec/controllers/lists_controller_spec.rb
RSpec.describe ListsController, type: :controller do
  let(:user) { create(:user, :verified) }
  let(:other_user) { create(:user) }
  let(:list) { create(:list, owner: user) }

  before { sign_in(user) }

  describe "GET #show" do
    it "returns 200 for authorized user" do
      get :show, params: { id: list }
      expect(response).to have_http_status(:success)
    end

    it "raises authorization error for unauthorized user" do
      sign_in(other_user)
      expect {
        get :show, params: { id: list }
      }.to raise_error(Pundit::NotAuthorizedError)
    end
  end

  describe "PATCH #update" do
    it "updates list and responds with turbo stream" do
      expect {
        patch :update,
              params: { id: list, list: { title: "Updated" } },
              headers: { "Accept" => "text/vnd.turbo-stream.html" }
      }.to change { list.reload.title }.to("Updated")
      
      expect(response.media_type).to match("text/vnd.turbo-stream")
    end

    it "returns unprocessable_entity on validation error" do
      patch :update, params: { id: list, list: { title: "" } }
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "denies access if not authorized" do
      sign_in(other_user)
      expect {
        patch :update, params: { id: list, list: { title: "Hacked" } }
      }.to raise_error(Pundit::NotAuthorizedError)
    end
  end

  describe "POST #create" do
    it "creates list with valid params" do
      expect {
        post :create, params: { list: { title: "New List" } }
      }.to change(List, :count).by(1)
    end

    it "responds with correct format" do
      post :create,
           params: { list: { title: "New List" } },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
      
      expect(response.media_type).to match("text/vnd.turbo-stream")
    end
  end

  describe "DELETE #destroy" do
    it "deletes list only if authorized" do
      expect {
        delete :destroy, params: { id: list }
      }.to change(List, :count).by(-1)
    end

    it "denies other users" do
      sign_in(other_user)
      expect {
        delete :destroy, params: { id: list }
      }.to raise_error(Pundit::NotAuthorizedError)
    end
  end
end
```

### Layer 4: System Tests (End-to-End Tests)

**Purpose:** Test complete user workflows with real browser interactions. These validate that all layers work together correctly.

**When to write system tests:**
- Complex multi-step workflows
- Real-time collaboration features
- User authentication flows
- Error states and edge cases

**When NOT to write system tests:**
- Simple CRUD operations (covered by controller tests)
- Business logic validation (covered by model tests)
- Single component rendering (test views aren't reliable)

**Example:**

```ruby
# spec/system/comment_workflows_spec.rb
RSpec.describe "Comment Workflows", type: :system, js: true do
  let(:owner) { create(:user, :verified) }
  let(:collaborator) { create(:user, :verified) }
  let(:list) { create(:list, owner: owner) }

  before do
    list.collaborators.create!(user: collaborator, permission: :comment)
  end

  scenario "User adds and sees comment in real-time" do
    sign_in_with_ui(collaborator)
    visit list_path(list)
    
    fill_in "Comment", with: "This is a great list!"
    click_button "Post Comment"
    
    expect(page).to have_text("This is a great list!")
    expect(page).to have_text(collaborator.name)
  end

  scenario "Multiple users see real-time comment updates" do
    using_session("owner") do
      sign_in_with_ui(owner)
      visit list_path(list)
    end

    using_session("collaborator") do
      sign_in_with_ui(collaborator)
      visit list_path(list)
    end

    using_session("collaborator") do
      fill_in "Comment", with: "Great work!"
      click_button "Post Comment"
      expect(page).to have_text("Great work!")
    end

    using_session("owner") do
      expect(page).to have_text("Great work!", wait: 5)
    end
  end

  scenario "User cannot comment without permission" do
    other_user = create(:user, :verified)
    
    sign_in_with_ui(other_user)
    visit list_path(list)
    
    expect(page).not_to have_field("Comment")
  end
end

# spec/system/real_time_collaboration_spec.rb
RSpec.describe "Real-Time Collaboration", type: :system, js: true do
  let(:owner) { create(:user, :verified) }
  let(:collaborator) { create(:user, :verified) }
  let(:list) { create(:list, owner: owner) }

  before do
    list.collaborators.create!(user: collaborator, permission: :edit)
  end

  scenario "Users see real-time item creation" do
    using_session("owner") do
      sign_in_with_ui(owner)
      visit list_path(list)
    end

    using_session("collaborator") do
      sign_in_with_ui(collaborator)
      visit list_path(list)
    end

    using_session("owner") do
      fill_in "Title", with: "New Task"
      click_button "Add Item"
      expect(page).to have_content("New Task")
    end

    using_session("collaborator") do
      expect(page).to have_content("New Task", wait: 5)
    end
  end

  scenario "Completion status updates in real-time" do
    item = create(:list_item, list: list, status: :pending)

    using_session("owner") do
      sign_in_with_ui(owner)
      visit list_path(list)
    end

    using_session("collaborator") do
      sign_in_with_ui(collaborator)
      visit list_path(list)
    end

    using_session("owner") do
      check "list_item_#{item.id}_completed"
      expect(page).to have_css("#list_item_#{item.id}.completed")
    end

    using_session("collaborator") do
      expect(page).to have_css("#list_item_#{item.id}.completed", wait: 5)
    end
  end
end
```

## Factories

Create consistent test data:

```ruby
# spec/factories/users.rb
FactoryBot.define do
  factory :user do
    sequence(:name) { |n| "User #{n}" }
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "SecurePass123" }
    password_confirmation { "SecurePass123" }

    trait :verified do
      email_verified_at { Time.current }
    end

    trait :admin do
      verified
      after(:create) { |user| user.add_role(:admin) }
    end
  end
end

# spec/factories/comments.rb
FactoryBot.define do
  factory :comment do
    content { Faker::Lorem.paragraph }
    association :user
    association :commentable, factory: :list

    trait :on_list_item do
      association :commentable, factory: :list_item
    end

    trait :with_children do
      after(:create) do |comment|
        create_list(:comment, 2, commentable: comment.commentable, parent: comment)
      end
    end
  end
end
```

## Test Helpers

Reusable utilities for common test operations:

```ruby
# spec/support/authentication_helpers.rb
module AuthenticationHelpers
  def sign_in(user)
    session[:user_id] = user.id
    Current.user = user
  end

  def sign_out
    session.clear
    Current.user = nil
  end

  def sign_in_as_admin(user = nil)
    user ||= create(:user, :verified, :admin)
    sign_in(user)
    user
  end

  def expect_unauthorized
    expect(response).to redirect_to(root_path)
    expect(flash[:alert]).to include("not authorized")
  end
end

RSpec.configure do |config|
  config.include AuthenticationHelpers, type: :controller
  config.include AuthenticationHelpers, type: :system
  config.include AuthenticationHelpers, type: :request
end

# spec/support/capybara_helpers.rb
module CapybaraHelpers
  def sign_in_with_ui(user)
    visit new_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: user.password
    click_button "Sign In"
  end

  def expect_turbo_stream_response
    expect(response.media_type).to match("text/vnd.turbo-stream")
  end

  def wait_for_turbo_stream
    expect(page).to have_css('[data-action*="turbo"]', visible: false, wait: 5)
  end
end

RSpec.configure do |config|
  config.include CapybaraHelpers, type: :system
end
```

## Running Tests

### Run All Tests
```bash
bundle exec rspec
```

### Run by Layer
```bash
# Model tests only
bundle exec rspec spec/models

# Controller tests only
bundle exec rspec spec/controllers

# Policy tests only
bundle exec rspec spec/policies

# Service tests only
bundle exec rspec spec/services

# System tests only (browser)
bundle exec rspec spec/system

# Production-ready tests (CI/Deployment)
bundle exec rails test:production_ready
```

### Run Specific Files
```bash
bundle exec rspec spec/models/list_spec.rb
bundle exec rspec spec/policies/list_policy_spec.rb
bundle exec rspec spec/controllers/lists_controller_spec.rb
```

### By Tag
```bash
bundle exec rspec --tag :focus                    # Only focused tests
bundle exec rspec --tag type:model                # Only model tests
bundle exec rspec --tag type:system               # Only system tests
bundle exec rspec --tag :slow, invert_selection  # Skip slow tests
```

### With Options
```bash
bundle exec rspec --format documentation         # Verbose output
bundle exec rspec --format progress               # Compact progress
bundle exec rspec --profile 10                   # Show 10 slowest tests
```

## Debugging Tests

```bash
# Run with debugging
bundle exec rspec --debug

# Run single test with detailed output
bundle exec rspec spec/models/list_spec.rb:10 --format documentation

# Show SQL queries
bundle exec rspec --require spec/helpers/sql_logger
```

### Browser Test Debugging

```ruby
# spec/support/capybara.rb
Capybara.register_driver(:cuprite_debug) do |app|
  Capybara::Cuprite::Driver.new(
    app,
    inspector: true,  # Show inspector
    headless: false   # See browser window
  )
end

# Run with:
# DRIVER=cuprite_debug bundle exec rspec spec/system/...
```

## Test Quality Guidelines

✅ **Do:**
- Test one behavior per spec
- Use clear, descriptive test descriptions
- Set up minimal data needed for the test
- Clean up after tests (Database Cleaner handles this)
- Mock external service calls (HTTP, email, APIs)
- Test both happy paths and edge cases
- Use appropriate layer for each test
- Keep tests focused and independent

❌ **Don't:**
- Create unnecessary factories or factories with too much data
- Test implementation details (test behavior instead)
- Make tests depend on each other (tests should be order-independent)
- Use hardcoded values (use Faker or factories)
- Test Rails framework code
- Make slow or flaky browser tests
- Test multiple behaviors in one test
- Skip database cleanup between tests

## Performance Tips

1. **Use `create` sparingly** - Prefer `build` when you don't need database persistence
2. **Batch factory creation** - Use `create_list` instead of loops
3. **Cache expensive data** - Use let/let! strategically
4. **Profile slow tests** - `rspec --profile 10` shows the slowest tests
5. **Mark slow tests** - Use `@slow` tag to skip slow tests in CI when needed
6. **Avoid database hits in unit tests** - Use mocks and stubs
7. **Parallel tests** - Consider `parallel_tests` gem for CI

## Adding Tests for New Features

When adding a new feature like the polymorphic `comments` model:

### 1. Start with Model Tests
```bash
touch spec/models/comment_spec.rb
```
Test validations, associations, and business logic.

### 2. Add Policy Tests (if authorization is involved)
```bash
touch spec/policies/comment_policy_spec.rb
```
Test authorization rules independently.

### 3. Add Controller/Request Tests
```bash
touch spec/controllers/comments_controller_spec.rb
```
Test HTTP layer, responses, and side effects.

### 4. Add System Tests (if user workflow is complex)
```bash
touch spec/system/comment_workflows_spec.rb
```
Test complete user workflows with browser automation.

### 5. Mark as Production-Ready
Once all tests pass and are stable, update `lib/tasks/test.rake`:

```ruby
namespace :test do
  desc "Run production-ready tests"
  task :production_ready do
    sh "bundle exec rspec " \
       "spec/models/user_spec.rb " \
       "spec/models/invitation_spec.rb " \
       "spec/models/session_spec.rb " \
       "spec/models/comment_spec.rb"  # Add here
  end
end
```

Update CI workflow (`.github/workflows/ci.yml`), then commit.

## CI/CD Integration

The GitHub Actions workflow runs production-ready tests on every push to `main` and every pull request:

```yaml
# .github/workflows/ci.yml
- name: Run production-ready tests
  env:
    RAILS_ENV: test
    DATABASE_URL: postgres://postgres:postgres@localhost:5432
  run: bundle exec rails test:production_ready
```

## Configuration

### RSpec Setup

```ruby
# spec/rails_helper.rb
require 'spec_helper'
require File.expand_path('../config/environment', __dir__)

abort("The Rails environment is running in production mode!") if Rails.env.production?

require 'rspec/rails'

Dir[Rails.root.join('spec/support/**/*.rb')].sort.each { |f| require f }

RSpec.configure do |config|
  config.fixture_path = "#{::Rails.root}/spec/fixtures"
  config.use_transactional_fixtures = true
  config.include Devise::Test::IntegrationHelpers, type: :request
  config.color = true
  config.default_formatter = 'doc' if ENV['CI'].present?
end
```

### Database Cleaner

```ruby
# spec/support/database_cleaner.rb
RSpec.configure do |config|
  config.before(:suite) do
    DatabaseCleaner.strategy = :transaction
    DatabaseCleaner.clean_with(:truncation)
  end

  config.around(:each) do |example|
    DatabaseCleaner.cleaning do
      example.run
    end
  end
end
```

### Capybara & Cuprite

```ruby
# spec/support/capybara.rb
Capybara.register_driver(:cuprite) do |app|
  Capybara::Cuprite::Driver.new(
    app,
    browser_options: { 'no-sandbox': nil },
    timeout: 10,
    process_timeout: 15,
    inspector: false
  )
end

Capybara.default_driver = :cuprite
Capybara.javascript_driver = :cuprite

require 'capybara/cuprite'
```

## Summary

Listopia's testing approach provides:

- **Clear organization** - Tests organized by layer with distinct responsibilities
- **Fast feedback** - Model and policy tests run quickly; system tests validate workflows
- **Incremental growth** - Add tests as features mature, mark as production-ready when stable
- **Maintainability** - Factories, helpers, and consistent patterns keep tests clean
- **Reliable deployments** - Only proven, production-ready tests run in CI
- **Comprehensive coverage** - Testing pyramid ensures all layers are validated

Test efficiently, validate thoroughly, deploy confidently.