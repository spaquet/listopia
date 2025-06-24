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
# Start PostgreSQL services
docker-compose up -d postgres postgres_test

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
  redirect_to verify_