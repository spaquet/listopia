# Listopia Dependencies

This document provides a comprehensive overview of all dependencies used in the Listopia Rails 8 application.

## Ruby Gems

### Core Framework
- **rails** (~> 8.0.2) - Ruby on Rails framework
- **pg** (~> 1.1) - PostgreSQL database adapter
- **puma** (>= 5.0) - Web server
- **bootsnap** - Boot time optimization through caching

### Asset Pipeline & Frontend
- **propshaft** - Modern asset pipeline for Rails
- **jsbundling-rails** - JavaScript bundling integration
- **cssbundling-rails** - CSS bundling integration
- **stimulus-rails** - Hotwire's JavaScript framework
- **turbo-rails** - Hotwire's SPA-like page accelerator
- **jbuilder** - JSON API builder

### Storage & Caching
- **solid_cache** - Database-backed Rails cache
- **solid_queue** - Database-backed Active Job backend
- **solid_cable** - Database-backed Action Cable adapter
- **image_processing** (~> 1.2) - Active Storage image variants

### Authentication & Authorization
- **bcrypt** (~> 3.1.7) - Password hashing for secure authentication
- **pundit** - Authorization library for Rails applications
- **rolify** - Role management library for Rails applications

### Business Logic & Features
- **friendly_id** - SEO-friendly URLs with slugs
- **acts-as-taggable-on** - Tagging functionality for Active Record
- **pagy** - Fast pagination library
- **noticed** - Notification system
- **positioning** - Drag & drop ordering for lists and items

### AI/LLM Integration
- **ruby_llm** - AI/LLM integration capabilities
- **multi_json** - JSON processing for MCP responses

### Development Dependencies
#### Development & Testing Group
- **debug** - Debugging tool (mri/windows platforms)
- **brakeman** - Static security vulnerability analysis
- **rubocop-rails-omakase** - Ruby style guide enforcement
- **rspec-rails** - RSpec testing framework
- **factory_bot_rails** - Test data factories
- **faker** - Fake data generation for testing

#### Development Only
- **web-console** - Interactive console on exception pages
- **letter_opener** - Email preview in development
- **dotenv-rails** - Environment variable management
- **annotaterb** - Model annotation tool
- **bullet** - N+1 query detection and unused eager loading tracker

#### Testing Only
- **capybara** - System testing framework
- **selenium-webdriver** - Browser automation for testing
- **shoulda-matchers** (~> 6.0) - Enhanced model validation testing
- **database_cleaner-active_record** - Test database cleanup
- **rails-controller-testing** - Controller testing utilities
- **rspec-retry** - Flaky test retry mechanism
- **timecop** - Time manipulation for testing

### Deployment & Performance
- **kamal** - Docker-based deployment tool
- **thruster** - HTTP asset caching and compression for Puma
- **tzinfo-data** - Timezone data (Windows/JRuby platforms)

## JavaScript Dependencies

### Package Manager
- **Bun** - Fast JavaScript package manager and runtime

### Core JavaScript Libraries
- **@hotwired/stimulus** (^3.2.2) - Modest JavaScript framework
- **@hotwired/turbo-rails** (^8.0.16) - SPA-like page accelerator

### CSS Framework
- **tailwindcss** (^4.1.11) - Utility-first CSS framework
- **@tailwindcss/cli** (^4.1.11) - Tailwind CSS command line interface

### UI Libraries
- **sortablejs** (^1.15.6) - Drag and drop sorting library for lists

## Stimulus Controllers

### Custom Stimulus Controllers
All controllers are custom-built for Listopia's specific needs:

#### Core Functionality Controllers
- **auto_save_controller.js** - Auto-save form inputs
- **dropdown_controller.js** - Dropdown menu management
- **modal_controller.js** - Modal dialog handling
- **toggle_controller.js** - Toggle switch components

#### List & Item Management
- **sortable_controller.js** - Drag & drop reordering using SortableJS
- **custom_select_controller.js** - Custom select dropdowns
- **inline_edit_controller.js** - Inline editing functionality
- **quick_add_controller.js** - Quick item addition

#### Real-time & Collaboration
- **realtime_controller.js** - Real-time updates via Turbo Streams
- **collaboration_controller.js** - Live collaboration features
- **progress_animation_controller.js** - Progress bar animations

#### User Experience
- **clipboard_controller.js** - Copy-to-clipboard functionality
- **flash_controller.js** - Flash message handling
- **keyboard_shortcuts_controller.js** - Global keyboard shortcuts
- **filters_controller.js** - List filtering functionality

#### Notifications
- **notifications_controller.js** - Notification management
- **notification_filters_controller.js** - Notification filtering

#### Chat/AI Features
- **chat_controller.js** - AI chat interface functionality

### Stimulus Components Integration
While we have many custom controllers, some are inspired by patterns from [stimulus-components.com](https://www.stimulus-components.com/):

#### Common Patterns Used
- **Clipboard functionality** - For sharing URLs and copying content
- **Modal dialogs** - For list sharing, editing, and confirmations  
- **Dropdown menus** - For user actions and list management
- **Custom selects** - For item types and filter options
- **Toggle switches** - For personal/professional list types

*Note: All controllers are custom implementations optimized for Listopia's specific use cases rather than direct imports from stimulus-components.com*

## Database Extensions

### PostgreSQL Extensions
- **pgcrypto** - UUID generation with `gen_random_uuid()`
- **plpgsql** - PostgreSQL procedural language

## Development Tools

### Build Tools
- **Bun** - Package management and building
- **Tailwind CSS CLI** - CSS compilation

### Code Quality
- **RuboCop Rails Omakase** - Ruby style enforcement
- **Brakeman** - Security scanning
- **Bullet** - Performance monitoring

### Testing Stack
- **RSpec** - Primary testing framework
- **Factory Bot** - Test data creation
- **Capybara + Selenium** - Browser-based testing
- **Database Cleaner** - Test isolation

## Architecture Notes

### Rails 8 Features Utilized
- **Solid Queue** - Background job processing
- **Solid Cache** - Database-backed caching
- **Solid Cable** - Database-backed WebSocket connections
- **Modern Credentials** - Secure configuration management
- **Zeitwerk Autoloading** - Efficient code loading

### Hotwire Stack
- **Turbo Frames** - Partial page updates
- **Turbo Streams** - Real-time collaborative features
- **Stimulus Controllers** - Progressive JavaScript enhancement

### Performance Optimizations
- **UUID Primary Keys** - Better scalability and security
- **Database Indexing** - Optimized query performance
- **Asset Compression** - Thruster for production performance
- **Efficient Loading** - Bullet gem prevents N+1 queries

### Security Features
- **bcrypt** - Secure password hashing
- **Pundit** - Comprehensive authorization
- **CSRF Protection** - Built into Rails
- **Brakeman** - Static security analysis

---

*Last updated: July 29, 2025*
*Rails Version: 8.0.2*
*Ruby Version: 3.4+*