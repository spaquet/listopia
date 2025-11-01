# Testing

Listopia uses **RSpec** as the sole testing framework. All tests follow RSpec conventions with clear structure, comprehensive coverage, and practical patterns.

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

## Browser Testing

Listopia uses **[Cuprite](https://github.com/rubycdp/cuprite)** as the headless browser driver for system tests with Capybara.

**Setup:**

```ruby
# Gemfile
group :test do
  gem 'cuprite'
end

# spec/support/capybara.rb
Capybara.register_driver(:cuprite) do |app|
  Capybara::Cuprite::Driver.new(
    app,
    browser_options: { 'no-sandbox': nil },
    timeout: 10,
    process_timeout: 15,
    inspector: false  # Set to true for debugging
  )
end

Capybara.default_driver = :cuprite
Capybara.javascript_driver = :cuprite

# spec/rails_helper.rb
config.include Capybara::DSL
```

## Running Tests

### All Tests
```bash
bundle exec rspec
```

### Specific Test Files
```bash
bundle exec rspec spec/models/user_spec.rb
bundle exec rspec spec/controllers/lists_controller_spec.rb
bundle exec rspec spec/system/authentication_spec.rb
```

### By Tag
```bash
bundle exec rspec --tag :focus                    # Only focused tests
bundle exec rspec --tag type:model                # Only model tests
bundle exec rspec --tag type:system               # Only system tests
bundle exec rspec --tag :slow, invert_selection  # Everything except slow tests
```

### With Options
```bash
bundle exec rspec --format documentation         # Verbose output
bundle exec rspec --format progress               # Compact progress
bundle exec rspec --profile 10                   # Show 10 slowest tests
bundle exec rspec --failure-exit-code 1          # Exit code on failure
```

## Test Structure

### Directory Organization

```
spec/
├── models/                 # Unit tests for models
│   ├── user_spec.rb
│   ├── list_spec.rb
│   └── list_item_spec.rb
├── controllers/            # Controller tests
│   ├── lists_controller_spec.rb
│   └── list_items_controller_spec.rb
├── requests/              # API/request specs
├── system/                # Browser/integration tests
│   ├── authentication_spec.rb
│   ├── list_management_spec.rb
│   └── real_time_collaboration_spec.rb
├── services/              # Service object tests
├── policies/              # Pundit policy tests
├── mailers/               # Email tests
├── factories/             # Factory Bot factories
│   ├── users.rb
│   ├── lists.rb
│   └── list_items.rb
├── support/               # RSpec helpers & configuration
│   ├── authentication_helpers.rb
│   ├── database_cleaner.rb
│   └── capybara.rb
└── rails_helper.rb        # RSpec configuration
```

## Model Tests

Test validations, associations, and business logic:

```ruby
# spec/models/list_spec.rb
RSpec.describe List, type: :model do
  describe "associations" do
    it { should belong_to(:owner).class_name("User") }
    it { should have_many(:list_items).dependent(:destroy) }
    it { should have_many(:collaborators) }
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
end
```

## Controller Tests

Test authorization, responses, and side effects:

```ruby
# spec/controllers/lists_controller_spec.rb
RSpec.describe ListsController, type: :controller do
  let(:user) { create(:user, :verified) }
  let(:list) { create(:list, owner: user) }

  before { sign_in(user) }

  describe "GET #index" do
    it "returns accessible lists" do
      create(:list, owner: user)
      create(:list)  # Other user's list
      
      get :index
      
      expect(response).to have_http_status(:success)
      expect(assigns(:lists).count).to eq(1)
    end
  end

  describe "POST #create" do
    it "creates list and responds with turbo stream" do
      expect {
        post :create, params: { list: { title: "New List" } },
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
      }.to change(List, :count).by(1)
      
      expect(response.media_type).to match("text/vnd.turbo-stream")
    end

    it "validates presence of title" do
      post :create, params: { list: { title: "" } }
      
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "PATCH #update" do
    it "denies access if not authorized" do
      other_user = create(:user)
      other_list = create(:list, owner: other_user)
      
      patch :update, params: {
        id: other_list, list: { title: "Hacked" }
      }
      
      expect(response).to redirect_to(root_path)
    end
  end
end
```

## System Tests (Browser Tests with Capybara)

Test user workflows with real browser interactions:

```ruby
# spec/system/authentication_spec.rb
RSpec.describe "User Authentication", type: :system, js: true do
  describe "Sign up" do
    it "creates new user and signs in" do
      visit new_registration_path
      
      fill_in "Name", with: "Jane Doe"
      fill_in "Email", with: "jane@example.com"
      fill_in "Password", with: "SecurePass123"
      click_button "Sign Up"
      
      expect(page).to have_text("Verify your email")
      expect(User.last.email).to eq("jane@example.com")
    end
  end

  describe "Sign in" do
    let(:user) { create(:user, :verified) }

    it "signs in with valid credentials" do
      visit new_session_path
      
      fill_in "Email", with: user.email
      fill_in "Password", with: user.password
      click_button "Sign In"
      
      expect(page).to have_current_path(dashboard_path)
      expect(page).to have_text(user.name)
    end

    it "shows error with invalid credentials" do
      visit new_session_path
      
      fill_in "Email", with: user.email
      fill_in "Password", with: "wrong-password"
      click_button "Sign In"
      
      expect(page).to have_text("Invalid email or password")
    end
  end

  describe "Magic link" do
    let(:user) { create(:user, :verified) }

    it "sends magic link email" do
      visit new_session_path
      
      fill_in "Email", with: user.email
      click_button "Send Magic Link"
      
      expect(page).to have_text("Check your email")
      expect(ActionMailer::Base.deliveries.last.to).to include(user.email)
    end

    it "authenticates with magic link token" do
      token = user.generate_token_for(:magic_link)
      
      visit authenticate_magic_link_path(token: token)
      
      expect(page).to have_current_path(dashboard_path)
    end
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
      sign_in owner
      visit list_path(list)
      expect(page).to have_css('[data-turbo-stream]', visible: false)
    end

    using_session("collaborator") do
      sign_in collaborator
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
      sign_in owner
      visit list_path(list)
    end

    using_session("collaborator") do
      sign_in collaborator
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

# spec/factories/lists.rb
FactoryBot.define do
  factory :list do
    sequence(:title) { |n| "List #{n}" }
    description { Faker::Lorem.paragraph }
    status { :active }
    association :owner, factory: :user

    trait :with_items do
      after(:create) do |list|
        create_list(:list_item, 5, list: list)
      end
    end

    trait :public do
      is_public { true }
      public_slug { SecureRandom.urlsafe_base64(8) }
    end
  end
end

# spec/factories/list_items.rb
FactoryBot.define do
  factory :list_item do
    sequence(:title) { |n| "Item #{n}" }
    description { Faker::Lorem.sentence }
    status { :pending }
    priority { :medium }
    association :list

    trait :completed do
      status { :completed }
      completed_at { Time.current }
    end

    trait :assigned do
      association :assigned_user, factory: :user
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
  
  # Include helper modules
  config.include Devise::Test::IntegrationHelpers, type: :request
  
  # Color output
  config.color = true
  
  # Documentation format
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

## Testing Patterns

### Test Real-Time Broadcasting

```ruby
RSpec.describe ListItem, type: :model do
  describe "#broadcast_created" do
    it "broadcasts to list collaborators" do
      list = create(:list)
      user = create(:user)
      list.collaborators.create!(user: user)
      
      expect {
        list.list_items.create!(title: "New item")
      }.to have_broadcasted_to("list_#{list.id}_user_#{user.id}")
    end
  end
end
```

### Test Authorization with Pundit

```ruby
RSpec.describe ListPolicy do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }
  let(:list) { create(:list, owner: user) }

  describe "#update?" do
    it "allows owner to update" do
      expect(ListPolicy.new(user, list)).to permit(:update)
    end

    it "denies other users" do
      expect(ListPolicy.new(other_user, list)).not_to permit(:update)
    end
  end
end
```

### Test Notifications

```ruby
RSpec.describe "Notification Broadcasting" do
  it "notifies collaborators of list update" do
    user = create(:user)
    collaborator = create(:user)
    list = create(:list, owner: user)
    list.collaborators.create!(user: collaborator)
    
    Current.user = user
    expect {
      list.update!(title: "Updated")
    }.to have_enqueued_job(Noticed::DeliveryJob)
  end
end
```

## Debugging Tests

```bash
# Run with debugging
bundle exec rspec --debug

# Run single test with detailed output
bundle exec rspec spec/models/user_spec.rb:10 --format documentation

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
- Use clear test descriptions (should...)
- Set up minimal data needed
- Clean up after tests
- Mock external services
- Test edge cases and errors

❌ **Don't:**
- Create unnecessary factories
- Test implementation details
- Make tests depend on each other
- Use hardcoded values
- Test Rails framework code
- Make slow/flaky browser tests

## CI/CD Integration

```yaml
# .github/workflows/tests.yml
name: Tests

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    
    services:
      postgres:
        image: postgres:15
        options: >-
          --health-cmd pg_isready
          --health-interval 10s
          --health-timeout 5s
          --health-retries 5

    steps:
      - uses: actions/checkout@v3
      - uses: ruby/setup-ruby@v1
        with:
          ruby-version: 3.4
          bundler-cache: true
      
      - run: bundle exec rails db:setup
      - run: bundle exec rspec
```

## Performance Tips

1. **Use `create` sparingly** - Prefer `build` when possible
2. **Batch factory creation** - `create_list` instead of loop
3. **Cache expensive data** - Use let/let! strategically
4. **Profile slow tests** - `rspec --profile 10`
5. **Mark slow tests** - Use `@slow` tag for CI skipping
6. **Parallel tests** - Use `parallel_tests` gem for CI

## Summary

Listopia uses **RSpec exclusively** with **Cuprite** for browser testing. This provides:

- **Consistent test framework** - No mixing of testing tools
- **Comprehensive coverage** - Unit, integration, and system tests
- **Clear patterns** - Factories, helpers, organized specs
- **Good performance** - Fast test runs with Cuprite
- **Real-time testing** - Proper Turbo Streams testing
- **Maintainable code** - Clear structure and helpers