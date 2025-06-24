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

- **Ruby 3.2+** (preferably using rbenv or rvm)
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
# Run a quick test to verify everything works
bundle exec rails test
bundle exec rspec # if using RSpec

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

# Run specific tests
bundle exec rails test test/models/user_test.rb

# Check code style
bundle exec rubocop

# View routes
bundle exec rails routes

# Reset database
bundle exec rails db:reset
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

### Test Structure

We use a combination of test frameworks:

- **Minitest** for unit and integration tests
- **RSpec** for behavior-driven testing (optional)
- **Capybara** for system/feature tests
- **Factory Bot** for test data creation

### Running Tests

```bash
# Run all tests
bundle exec rails test

# Run specific test files
bundle exec rails test test/models/user_test.rb
bundle exec rails test test/controllers/lists_controller_test.rb

# Run system tests
bundle exec rails test:system

# Run with coverage (if configured)
COVERAGE=true bundle exec rails test
```

### Writing Tests

#### Model Tests
```ruby
# test/models/list_test.rb
require "test_helper"

class ListTest < ActiveSupport::TestCase
  test "should calculate completion percentage correctly" do
    list = create(:list)
    create_list(:list_item, 3, list: list)
    create_list(:list_item, 2, list: list, completed: true)
    
    assert_equal 40.0, list.completion_percentage
  end
  
  test "should require title" do
    list = build(:list, title: nil)
    assert_not list.valid?
    assert_includes list.errors[:title], "can't be blank"
  end
end
```

#### Controller Tests
```ruby
# test/controllers/lists_controller_test.rb
require "test_helper"

class ListsControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = create(:user)
    @list = create(:list, owner: @user)
    sign_in_as(@user)
  end
  
  test "should get index" do
    get lists_path
    assert_response :success
    assert_select "h1", "My Lists"
  end
  
  test "should create list" do
    assert_difference("List.count") do
      post lists_path, params: { list: { title: "New List" } }
    end
    assert_redirected_to list_path(List.last)
  end
end
```

#### System Tests
```ruby
# test/system/lists_test.rb
require "application_system_test_case"

class ListsTest < ApplicationSystemTestCase
  test "user can create a new list" do
    user = create(:user)
    sign_in_as(user)
    
    visit lists_path
    click_on "New List"
    
    fill_in "Title", with: "My Test List"
    fill_in "Description", with: "A list for testing"
    click_on "Create List"
    
    assert_text "List was successfully created"
    assert_text "My Test List"
  end
end
```

### Test Data with Factory Bot

```ruby
# test/factories/users.rb
FactoryBot.define do
  factory :user do
    name { Faker::Name.full_name }
    email { Faker::Internet.unique.email }
    password { "password123" }
    email_verified_at { Time.current }
  end
end

# test/factories/lists.rb
FactoryBot.define do
  factory :list do
    title { Faker::Lorem.words(number: 3).join(" ").titleize }
    description { Faker::Lorem.paragraph }
    status { :active }
    association :owner, factory: :user
  end
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
bundle exec rails test

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

# Make changes, test locally
bundle exec rails test

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

# Debug in views
<% console %> # Opens web console

# Debug in controllers
binding.pry # If pry gem is available

# Check logs
tail -f log/development.log
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
- **Background job processing** for email delivery
- **Configurable SMTP** for different environments

## Getting Help

### Resources

- **Rails Guides**: https://guides.rubyonrails.org/
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

**Asset compilation issues:**
```bash
# Rebuild assets
bun install
bun run build:css
```

**Test failures:**
```bash
# Reset test database
RAILS_ENV=test bundle exec rails db:reset
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