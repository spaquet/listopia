# Contributing to Listopia

Thank you for your interest in contributing to Listopia! This guide will help you get started with setting up your development environment and contributing to the project.

## Table of Contents

- [Development Setup](#development-setup)
- [Getting Started](#getting-started)
- [Making Contributions](#making-contributions)
- [Code Standards](#code-standards)
- [Testing](#testing)
- [Pull Request Process](#pull-request-process)
- [Development Workflow](#development-workflow)
- [Architecture Overview](#architecture-overview)

## Development Setup

### Prerequisites

Ensure you have the following installed on your development machine:

- **Ruby 3.4+** (preferably using rbenv or rvm)
- **Node.js 18+** (for JavaScript dependencies)
- **Bun** (JavaScript package manager)
- **Git**
- **Docker & Docker Compose** (for database services)

### 1. Fork and Clone the Repository

```bash
# Fork the repository on GitHub, then clone your fork
git clone https://github.com/YOUR_USERNAME/listopia.git
cd listopia

# Add the original repository as upstream
git remote add upstream https://github.com/ORIGINAL_OWNER/listopia.git
```

### 2. Install Ruby Dependencies

```bash
# Install Ruby version (if using rbenv)
rbenv install $(cat .ruby-version)
rbenv local $(cat .ruby-version)

# Install gems
bundle install
```

### 3. Install JavaScript Dependencies

```bash
# Install Bun if not already installed
curl -fsSL https://bun.sh/install | bash

# Install JavaScript dependencies
bun install
```

### 4. Database Setup with Docker

```bash
# Start PostgreSQL service
docker-compose up -d postgres

# Wait for PostgreSQL to be ready (check with)
docker-compose logs postgres

# Create and setup databases
bundle exec rails db:create
bundle exec rails db:migrate
bundle exec rails db:seed

# Setup test database
RAILS_ENV=test bundle exec rails db:create db:migrate
```

### 5. Environment Configuration

```bash
# Copy environment file (if exists)
cp .env.example .env

# Or create your own .env file with necessary variables
cat > .env << EOF
# Database configuration (should match docker-compose.yml)
LISTOPIA_DATABASE_HOST=localhost
LISTOPIA_DATABASE_USERNAME=postgres
LISTOPIA_DATABASE_PASSWORD=postgres
LISTOPIA_DATABASE_PORT=5432

# Development settings
RAILS_ENV=development
EOF
```

### 6. Start the Development Server

```bash
# Start the Rails server
bundle exec rails server

# In another terminal, start the asset watcher (if needed)
bun run build:css --watch
```

Your application should now be running at `http://localhost:3000`!

### 7. Verify Setup

```bash
# Run the smoke test to verify everything works
bundle exec rspec spec/smoke_test_spec.rb

# Run all tests
bundle exec rspec

# Check that you can access the application
curl http://localhost:3000/up
```

## Getting Started

### Understanding the Codebase

Listopia is a Rails 8 application with the following key features:

- **Rails 8 with Hotwire** - Real-time updates using Turbo Streams
- **PostgreSQL with UUIDs** - All models use UUID primary keys
- **Tailwind CSS 4** - Modern responsive design
- **Custom Authentication** - Email/password + magic link authentication
- **Real-time Collaboration** - Live list updates for multiple users
- **Email Integration** - Verification and notification emails

### Key Directories

```
app/
├── controllers/           # Request handling and business logic
├── models/               # Data models and business logic
├── views/                # HTML templates and partials
├── services/             # Complex business logic extraction
├── mailers/              # Email templates and sending logic
├── javascript/           # Stimulus controllers and JS
└── assets/              # CSS and other assets

spec/
├── models/              # Model unit tests
├── controllers/         # Controller tests
├── requests/            # API/request specs
├── system/              # Browser/integration tests
├── services/            # Service object tests
├── factories/           # FactoryBot factories
├── support/             # RSpec helpers and configuration
├── rails_helper.rb      # RSpec Rails configuration
└── spec_helper.rb       # RSpec base configuration

config/
├── routes.rb            # URL routing configuration
├── database.yml         # Database configuration
└── environments/        # Environment-specific settings
```

### Development Tools

**Useful commands:**
```bash
# Rails console
bundle exec rails console

# Database console
bundle exec rails dbconsole

# Run all tests
bundle exec rspec

# Run specific test files
bundle exec rspec spec/models/user_spec.rb
bundle exec rspec spec/controllers/lists_controller_spec.rb

# Run tests by type
bundle exec rspec --tag type:model
bundle exec rspec --tag type:system

# Run with detailed output
bundle exec rspec --format documentation

# Run only failing tests
bundle exec rspec --only-failures

# Check code style
bundle exec rubocop

# View routes
bundle exec rails routes

# Reset database
bundle exec rails db:reset

# Reset test database
RAILS_ENV=test bundle exec rails db:reset
```

## Making Contributions

### Types of Contributions

We welcome several types of contributions:

- 🐛 **Bug fixes** - Fix issues and improve stability
- ✨ **New features** - Add functionality that enhances the app
- 📚 **Documentation** - Improve guides, comments, and examples
- 🎨 **UI/UX improvements** - Enhance design and user experience
- ⚡ **Performance** - Optimize speed and resource usage
- 🧪 **Tests** - Add or improve test coverage
- 🔧 **Refactoring** - Improve code quality and maintainability

### Finding Issues to Work On

1. **Check the issues tab** for `good first issue` or `help wanted` labels
2. **Look for TODO comments** in the codebase
3. **Review the project roadmap** for planned features
4. **Use the application** and identify areas for improvement

### Before You Start

1. **Check existing issues** to avoid duplicate work
2. **Create an issue** for significant changes to discuss the approach
3. **Claim an issue** by commenting that you'd like to work on it
4. **Fork the repository** and create a feature branch

## Code Standards

### Ruby Style Guidelines

We follow standard Ruby and Rails conventions:

```ruby
# Good - descriptive method names
def calculate_completion_percentage
  return 0 if list_items.empty?
  (completed_items.count.to_f / list_items.count * 100).round(2)
end

# Good - clear variable names
user_lists = current_user.accessible_lists
collaboration_count = list.list_collaborations.count

# Good - consistent indentation and spacing
if user.email_verified?
  sign_in(user)
  redirect_to dashboard_path
else
  redirect_to verify_email_path
end
```

### JavaScript/Stimulus Guidelines

```javascript
// Good - descriptive controller and action names
export default class extends Controller {
  static targets = ["menu", "button"]
  
  connect() {
    this.close = this.close.bind(this)
  }
  
  toggle(event) {
    event.preventDefault()
    if (this.menuTarget.classList.contains("hidden")) {
      this.open()
    } else {
      this.close()
    }
  }
}
```

### CSS/Tailwind Guidelines

```erb
<!-- Good - semantic class combinations -->
<div class="bg-white rounded-lg shadow-sm border border-gray-200 p-6">
  <h2 class="text-lg font-medium text-gray-900 mb-4">
    List Title
  </h2>
</div>

<!-- Good - responsive design patterns -->
<div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6">
  <!-- Grid items -->
</div>
```

### Database Guidelines

```ruby
# Good - proper UUID usage
class CreateLists < ActiveRecord::Migration[8.0]
  def change
    create_table :lists, id: :uuid do |t|
      t.string :title, null: false
      t.text :description
      t.references :user, null: false, foreign_key: true, type: :uuid
      t.timestamps
    end
    
    add_index :lists, :user_id
    add_index :lists, :created_at
  end
end
```

### Model Guidelines

```ruby
# Good - clear associations and validations
class List < ApplicationRecord
  belongs_to :owner, class_name: "User", foreign_key: "user_id"
  has_many :list_items, dependent: :destroy
  has_many :list_collaborations, dependent: :destroy
  
  validates :title, presence: true, length: { maximum: 255 }
  
  enum :status, {
    draft: 0,
    active: 1,
    completed: 2,
    archived: 3
  }, prefix: true
  
  def completion_percentage
    return 0 if list_items.empty?
    completed_items = list_items.where(completed: true).count
    ((completed_items.to_f / list_items.count) * 100).round(2)
  end
end
```

## Testing

Listopia uses **RSpec** as the sole testing framework with Capybara for system tests and Factory Bot for test data generation.

### Test Structure

We use RSpec with the following test types:

- **Model specs** (`spec/models/`) - Unit tests for validations and associations
- **Controller specs** (`spec/controllers/`) - Request/response tests
- **Request specs** (`spec/requests/`) - API endpoint tests
- **System specs** (`spec/system/`) - Browser integration tests with Capybara
- **Service specs** (`spec/services/`) - Service object tests
- **Policy specs** (`spec/policies/`) - Pundit authorization tests

### Running Tests

```bash
# Run all tests
bundle exec rspec

# Run specific test files
bundle exec rspec spec/models/user_spec.rb
bundle exec rspec spec/controllers/lists_controller_spec.rb
bundle exec rspec spec/system/authentication_spec.rb

# Run by type
bundle exec rspec --tag type:model
bundle exec rspec --tag type:controller
bundle exec rspec --tag type:system

# Run focused tests
bundle exec rspec --tag :focus

# Run with different formats
bundle exec rspec --format documentation         # Detailed output
bundle exec rspec --format progress              # Compact progress dots
bundle exec rspec --profile 10                   # Show 10 slowest tests

# Run only previously failing tests
bundle exec rspec --only-failures

# Run with coverage (if configured)
COVERAGE=true bundle exec rspec
```

### Writing Tests

#### Model Tests

```ruby
# spec/models/list_spec.rb
RSpec.describe List, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:owner).class_name("User") }
    it { is_expected.to have_many(:list_items).dependent(:destroy) }
    it { is_expected.to have_many(:list_collaborations) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:title) }
    it { is_expected.to validate_length_of(:title).is_at_most(255) }
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
end
```

#### Controller Tests

```ruby
# spec/controllers/lists_controller_spec.rb
RSpec.describe ListsController, type: :controller do
  let(:user) { create(:user, :verified) }
  let(:list) { create(:list, owner: user) }

  before { sign_in(user) }

  describe "GET #index" do
    it "returns success" do
      get :index
      expect(response).to have_http_status(:success)
    end

    it "assigns lists" do
      get :index
      expect(assigns(:lists)).to be_present
    end
  end

  describe "POST #create" do
    it "creates a new list" do
      expect {
        post :create, params: { list: { title: "New List" } }
      }.to change(List, :count).by(1)
    end

    it "redirects to the list" do
      post :create, params: { list: { title: "New List" } }
      expect(response).to redirect_to(list_path(List.last))
    end
  end
end
```

#### System Tests

```ruby
# spec/system/lists_spec.rb
RSpec.describe "Lists", type: :system do
  let(:user) { create(:user, :verified) }

  before do
    driven_by(:cuprite)
    sign_in_with_ui(user)
  end

  it "user can create a new list" do
    visit lists_path
    click_on "New List"
    
    fill_in "Title", with: "My Test List"
    fill_in "Description", with: "A list for testing"
    click_on "Create List"
    
    expect(page).to have_text("List was successfully created")
    expect(page).to have_text("My Test List")
  end

  it "displays list items in real-time" do
    list = create(:list, owner: user)
    visit list_path(list)
    
    expect(page).to have_text(list.title)
  end
end
```

### Test Data with Factory Bot

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

### Test Helpers

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

  def sign_in_with_ui(user)
    visit new_session_path
    fill_in "Email", with: user.email
    fill_in "Password", with: user.password
    click_button "Sign In"
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
```

## Pull Request Process

### 1. Create a Feature Branch

```bash
# Create and switch to a new branch
git checkout -b feature/add-list-templates

# Or for bug fixes
git checkout -b fix/email-verification-bug
```

### 2. Make Your Changes

- **Follow the coding standards** outlined above
- **Write tests** for new functionality
- **Update documentation** if needed
- **Commit frequently** with clear messages

### 3. Commit Guidelines

```bash
# Good commit messages
git commit -m "Add list template feature for faster list creation"
git commit -m "Fix email verification token expiration issue"
git commit -m "Update list sharing UI with better visual feedback"

# Include issue numbers when applicable
git commit -m "Fix authentication redirect loop (fixes #123)"
```

### 4. Keep Your Branch Updated

```bash
# Fetch latest changes from upstream
git fetch upstream

# Rebase your branch on the latest main
git rebase upstream/main

# Or merge if rebasing is complex
git merge upstream/main
```

### 5. Run Tests and Checks

```bash
# Ensure all tests pass
bundle exec rspec

# Run specific test suites
bundle exec rspec spec/models
bundle exec rspec spec/system

# Check code style
bundle exec rubocop

# Check for security issues
bundle exec brakeman

# Verify the application starts
bundle exec rails server
```

### 6. Submit Pull Request

1. **Push your branch** to your fork
2. **Create a pull request** on GitHub
3. **Fill out the PR template** with:
   - Description of changes
   - Issue numbers addressed
   - Testing instructions
   - Screenshots (for UI changes)

### 7. PR Review Process

- **Be responsive** to feedback and questions
- **Make requested changes** promptly
- **Ask for clarification** if feedback is unclear
- **Update tests** if implementation changes
- **Squash commits** if requested before merge

## Development Workflow

### Daily Development

```bash
# Start your development session
docker-compose up -d postgres
bundle exec rails server

# In another terminal, watch tests
bundle exec rspec --format documentation --color

# Make changes, test locally
bundle exec rspec spec/models
bundle exec rspec spec/system

# Commit changes
git add .
git commit -m "Descriptive commit message"

# Push to your fork
git push origin feature-branch-name
```

### Working with Real-time Features

Listopia uses Hotwire Turbo Streams for real-time updates:

```ruby
# Controller action
def toggle_completion
  @list_item.toggle_completion!
  
  respond_with_turbo_stream do
    render :toggle_completion
  end
end
```

```erb
<!-- Corresponding Turbo Stream template -->
<%= turbo_stream.replace "list_item_#{@list_item.id}" do %>
  <%= render "list_items/item", item: @list_item %>
<% end %>
```

### Testing Real-time Features

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

### Working with Email Features

Test emails in development:

```bash
# Emails are opened automatically with letter_opener gem
# Or use MailHog if you prefer (uncomment in docker-compose.yml)
docker-compose up -d mailhog

# Access MailHog UI at http://localhost:8025
```

### Debugging Tips

```ruby
# Use Rails console for debugging
bundle exec rails console

# Debug in RSpec with pry
require 'pry'
binding.pry

# Debug specific tests
bundle exec rspec spec/models/user_spec.rb --pry

# Check logs
tail -f log/development.log

# Run tests with debugging output
bundle exec rspec --format documentation --color
```

## Architecture Overview

### Authentication System

Listopia uses a custom authentication system:

- **Email/password authentication** with bcrypt
- **Magic link authentication** for passwordless sign-in
- **Email verification** required for account activation
- **Session management** with secure session handling

### Real-time Collaboration

- **Turbo Streams** for live updates
- **Stimulus controllers** for client-side interactions
- **Optimistic UI updates** for better user experience
- **Permission-based access** to lists and items

### Database Design

- **UUID primary keys** for all models
- **PostgreSQL** with advanced features
- **Optimized indexes** for performance
- **Soft dependencies** for flexible associations

### Email System

- **Action Mailer** for email sending
- **HTML and text templates** for all emails
- **Background job processing** with Solid Queue
- **Configurable SMTP** for different environments

## Getting Help

### Resources

- **Rails Guides**: https://guides.rubyonrails.org/
- **RSpec Documentation**: https://rspec.info/
- **Hotwire Documentation**: https://hotwired.dev/
- **Tailwind CSS**: https://tailwindcss.com/docs
- **Stimulus Handbook**: https://stimulus.hotwired.dev/handbook/introduction

### Communication

- **GitHub Issues** for bug reports and feature requests
- **GitHub Discussions** for questions and general discussion
- **Pull Request comments** for code-specific questions

### Common Issues

**Database connection issues:**
```bash
# Reset database
docker-compose down
docker-compose up -d postgres
bundle exec rails db:reset
```

**Test database issues:**
```bash
# Reset test database
RAILS_ENV=test bundle exec rails db:reset
```

**Asset compilation issues:**
```bash
# Rebuild assets
bun install
bun run build:css
```

**Test failures:**
```bash
# Run failing tests with detailed output
bundle exec rspec --only-failures --format documentation

# Run specific test with debugging
bundle exec rspec spec/models/user_spec.rb --pry
```

## Recognition

Contributors who make significant contributions will be:

- **Listed in the README** contributors section
- **Mentioned in release notes** for major contributions
- **Invited to join** the core team for ongoing contributors

## Questions?

Don't hesitate to ask questions! Whether you're:

- **New to Rails** and learning the framework
- **Experienced** but unfamiliar with our codebase
- **Unsure** about the best approach for a feature
- **Stuck** on a technical issue

We're here to help and want you to succeed. Open an issue, start a discussion, or reach out to the maintainers directly.

Thank you for contributing to Listopia! 🚀