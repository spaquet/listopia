# Listopia Documentation

Welcome to the Listopia documentation hub! This directory contains comprehensive guides, architectural decisions, and implementation details for the Listopia Rails 8 application.

## 📋 Available Documentation

### Core System Documentation

- **[NOTIFICATION.md](NOTIFICATION.md)** - Complete guide to the notification system
  - Supported notification scenarios (9 key use cases)
  - Model vs Controller implementation patterns
  - Noticed gem integration and best practices
  - User preference management and testing strategies

### Planned Documentation

- **[AUTHENTICATION.md](AUTHENTICATION.md)** *(Coming Soon)* - Authentication system overview
  - Rails 8 authentication implementation
  - Magic link passwordless authentication
  - Email verification workflow
  - Session management

- **[COLLABORATION.md](COLLABORATION.md)** *(Coming Soon)* - List sharing and collaboration
  - Permission levels (read vs collaborate)
  - Invitation system for registered and unregistered users
  - Public list sharing with secure URLs
  - Real-time collaboration features

- **[REAL_TIME.md](REAL_TIME.md)** *(Coming Soon)* - Hotwire and real-time features
  - Turbo Streams implementation
  - Stimulus controllers
  - WebSocket integration patterns
  - Progressive enhancement strategies

- **[DATABASE.md](DATABASE.md)** *(Coming Soon)* - Database design and patterns
  - UUID primary key strategy
  - PostgreSQL optimizations
  - Model associations and validations
  - Migration best practices

- **[API.md](API.md)** *(Coming Soon)* - API design and endpoints
  - RESTful API conventions
  - JSON serialization patterns
  - Authentication for API access
  - Rate limiting and security

- **[DEPLOYMENT.md](DEPLOYMENT.md)** *(Coming Soon)* - Production deployment guide
  - Rails 8 production configuration
  - Solid Queue background jobs
  - Environment variables and secrets
  - Performance monitoring

- **[TESTING.md](TESTING.md)** *(Coming Soon)* - Testing strategies and patterns
  - RSpec configuration and best practices
  - Model, controller, and integration testing
  - JavaScript testing with Stimulus
  - Test data management with FactoryBot

## 🏗️ Architecture Overview

Listopia is built as a modern Rails 8 application showcasing:

- **Rails 8.0+** with latest features including Solid Queue
- **Hotwire Turbo Streams** for real-time collaboration
- **UUID Primary Keys** throughout for better security
- **Passwordless Authentication** with magic links
- **Responsive Design** with Tailwind CSS 4.1
- **Progressive Enhancement** with Stimulus controllers

## 🎯 Documentation Goals

Each document in this collection aims to:

- **Explain the "why"** behind architectural decisions
- **Provide practical examples** for common use cases
- **Include testing strategies** for reliable code
- **Offer troubleshooting guides** for common issues
- **Maintain consistency** across the application

## 📖 How to Use This Documentation

### For New Developers
1. Start with **AUTHENTICATION.md** to understand user management
2. Review **DATABASE.md** for data model relationships
3. Read **COLLABORATION.md** for core business logic
4. Explore **REAL_TIME.md** for interactive features

### For Feature Development
1. Check relevant documentation before implementing new features
2. Follow established patterns and conventions
3. Update documentation when adding new functionality
4. Include tests following documented testing strategies

### For Debugging
1. Consult troubleshooting sections in relevant docs
2. Use debugging commands provided in each guide
3. Check common issues and solutions

## 🤝 Contributing to Documentation

When adding new documentation:

1. **Follow the established format**
   - Clear overview section
   - Practical examples with code
   - Best practices and patterns
   - Troubleshooting guide

2. **Keep it practical**
   - Focus on real-world usage
   - Include copy-pasteable code examples
   - Explain both what and why

3. **Update this README**
   - Add new documents to the appropriate section
   - Include brief description of contents
   - Maintain logical organization

## 🔗 External Resources

### Rails 8 Resources
- [Rails 8.0 Release Notes](https://edgeguides.rubyonrails.org/8_0_release_notes.html)
- [Solid Queue Documentation](https://github.com/rails/solid_queue)
- [Rails Authentication Guide](https://guides.rubyonrails.org/security.html)

### Gems & Libraries
- [Noticed Gem Documentation](https://github.com/excid3/noticed)
- [Hotwire Documentation](https://hotwired.dev/)
- [Tailwind CSS Documentation](https://tailwindcss.com/)
- [Stimulus Handbook](https://stimulus.hotwired.dev/handbook/introduction)

### Testing Resources
- [RSpec Rails Documentation](https://github.com/rspec/rspec-rails)
- [FactoryBot Documentation](https://github.com/thoughtbot/factory_bot)
- [Capybara Documentation](https://github.com/teamcapybara/capybara)

## 📝 Document Status Legend

- ✅ **Complete** - Comprehensive documentation ready for use
- 🚧 **In Progress** - Actively being written or updated  
- 📋 **Planned** - Scheduled for creation
- 🔄 **Needs Update** - Requires revision due to code changes

Current Status:
- ✅ NOTIFICATION.md
- 📋 All other planned documents

---

*This documentation is maintained by the Listopia development team. For questions or suggestions, please create an issue or contribute directly to the doc