# Claude.md - Listopia Development Instructions

You are assisting with development of **Listopia**, a modern collaborative list management application built with Rails 8. Focus on maintaining the established architecture, patterns, and technical standards.

## Technology Stack & Architecture

### Core Framework
- **Rails 8.0.2** with latest features and conventions
- **Ruby 3.4+** following modern Ruby patterns
- **PostgreSQL** as primary database with advanced features
- **UUID Primary Keys** for all models (security and scalability)
- **Solid Queue** for background job processing (Rails 8 default)
- **Solid Cache** for caching layer
- **RubyLLM** for AI chat integration

### Frontend & Real-time
- **Hotwire Turbo Streams** for real-time updates without page refreshes
- **Stimulus Controllers** for progressive JavaScript enhancement
- **Tailwind CSS 4.1** for responsive, mobile-first design
- **Bun** for JavaScript package management
- **Persistent AI Chat** with context awareness

### Database Design Principles
- **UUID Primary Keys** - All models must use UUIDs, never integer IDs
- **PostgreSQL Extensions** - Leverage pgcrypto, proper indexing
- **Optimized Queries** - Always consider N+1 prevention with includes/joins
- **Soft Dependencies** - Flexible associations with proper null handling

## Core Models & Relationships

### Authentication & Users
```ruby
# User model with Rails 8 authentication patterns
class User < ApplicationRecord
  has_secure_password
  has_many :lists, foreign_key: 'owner_id', dependent: :destroy
  has_many :list_collaborations, dependent: :destroy
  has_many :collaborated_lists, through: :list_collaborations, source: :list
  has_many :chats, dependent: :destroy
  has_many :sessions, dependent: :destroy
  
  # Rails 8 token generation for magic links
  generates_token_for :magic_link, expires_in: 15.minutes
  generates_token_for :email_verification, expires_in: 24.hours
end
```

### Core Entities
```ruby
# All models use UUID primary keys
class List < ApplicationRecord
  belongs_to :owner, class_name: 'User'
  has_many :list_items, dependent: :destroy
  has_many :list_collaborations, dependent: :destroy
  has_many :collaborators, through: :list_collaborations, source: :user
  
  enum :status, { draft: "draft", active: "active", completed: "completed", archived: "archived" }
end

class ListItem < ApplicationRecord
  belongs_to :list
  belongs_to :assigned_user, class_name: 'User', optional: true
  
  enum :priority, { low: "low", medium: "medium", high: "high" }
  enum :status, { pending: "pending", in_progress: "in_progress", completed: "completed" }
end
```

### AI Chat System
```ruby
class Chat < ApplicationRecord
  acts_as_chat # RubyLLM integration
  belongs_to :user
  has_many :messages, dependent: :destroy
  
  enum :status, { active: "active", archived: "archived", completed: "completed" }
  enum :conversation_state, { stable: "stable", needs_cleanup: "needs_cleanup", error: "error" }
end

class Message < ApplicationRecord
  acts_as_message # RubyLLM integration
  belongs_to :chat
  belongs_to :user, optional: true # Assistant messages don't have a user
  
  enum :role, { user: "user", assistant: "assistant", system: "system", tool: "tool" }
end
```

## Development Patterns & Standards

### Controller Patterns
```ruby
# Follow RESTful conventions with proper authorization
class ListsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_list, only: [:show, :edit, :update, :destroy]
  before_action :authorize_list_access!, only: [:show, :edit, :update, :destroy]
  
  def create
    @list = current_user.lists.build(list_params)
    if @list.save
      respond_to do |format|
        format.html { redirect_to @list }
        format.turbo_stream # Real-time updates
      end
    end
  end
  
  private
  
  def authorize_list_access!
    authorize @list # Using Pundit for authorization
  end
end
```

### Service Object Patterns
```ruby
# Use service objects for complex business logic
class ListSharingService
  def initialize(list, user)
    @list = list
    @user = user
  end
  
  def share_with(email, permission_level: 'read')
    # Complex sharing logic with email invitations
    # Handle non-registered users
    # Send notifications
  end
end

# AI-specific services
class McpService
  def initialize(user:, context: {}, chat: nil)
    @user = user
    @context = context # Current page, selected items, permissions
    @chat = chat || user.current_chat
    @tools = McpTools.new(user, context)
  end
  
  def process_message(message_content)
    # AI message processing with error recovery
    # Context-aware responses
    # Tool execution with permission validation
  end
end
```

### Real-time Updates with Turbo Streams
```ruby
# Controller actions should respond with Turbo Streams
def update
  if @list_item.update(list_item_params)
    respond_to do |format|
      format.turbo_stream do
        render turbo_stream: [
          turbo_stream.replace(@list_item),
          turbo_stream.replace("progress-#{@list.id}", 
            partial: "lists/progress", locals: { list: @list })
        ]
      end
    end
  end
end
```

### Database Migration Standards
```ruby
# Always use UUIDs for primary keys
class CreateLists < ActiveRecord::Migration[8.0]
  def change
    enable_extension 'pgcrypto' unless extension_enabled?('pgcrypto')
    
    create_table :lists, id: :uuid do |t|
      t.references :owner, null: false, foreign_key: { to_table: :users }, type: :uuid
      t.string :title, limit: 255, null: false
      t.text :description
      t.string :status, default: 'draft', null: false
      t.boolean :is_public, default: false
      t.json :metadata, default: {}
      
      t.timestamps
    end
    
    add_index :lists, [:owner_id, :status]
    add_index :lists, :is_public, where: "is_public = true"
  end
end
```

## Code Quality Standards

### Security Requirements
- **Always validate user input** with strong parameters
- **Authorize every action** using Pundit policies
- **CSRF protection** enabled by default
- **SQL injection prevention** through parameterized queries
- **XSS protection** via Rails built-in helpers

### Performance Guidelines
- **Prevent N+1 queries** with includes, joins, preload
- **Database indexes** for all foreign keys and frequent queries
- **Pagination** with Pagy for large result sets
- **Caching** with Solid Cache for expensive operations
- **Background jobs** for slow operations

### Testing Standards
```ruby
# Model tests with comprehensive coverage
RSpec.describe List, type: :model do
  it { should belong_to(:owner).class_name('User') }
  it { should have_many(:list_items).dependent(:destroy) }
  it { should validate_presence_of(:title) }
  it { should validate_length_of(:title).is_at_most(255) }
end

# Integration tests for user workflows
RSpec.describe "List Management", type: :system do
  it "creates list with real-time updates" do
    # Test Turbo Stream functionality
    # Test AI chat integration
    # Test collaboration features
  end
end
```

## AI Chat Integration Guidelines

### Tool Development
```ruby
# AI tools must validate permissions before execution
class McpTools
  def create_planning_list(title:, description:, items: [])
    # Validate user can create lists
    return error_response unless @user.can_create_lists?
    
    list = @user.lists.create!(
      title: title,
      description: description,
      status: 'active'
    )
    
    # Add items with proper associations
    items.each { |item| list.list_items.create!(content: item) }
    
    success_response(list)
  end
end
```

### Context Awareness
```ruby
# Always provide relevant context to AI
def gather_chat_context
  {
    page: "#{controller_name}##{action_name}",
    list_id: params[:id],
    list_title: @list&.title,
    user_permissions: current_user.permissions_for(@list),
    selected_items: session[:selected_items] || []
  }
end
```

## Error Handling & Recovery

### Graceful Degradation
```ruby
# AI chat should degrade gracefully
rescue StandardError => e
  Rails.logger.error "AI processing failed: #{e.message}"
  
  if e.is_a?(ConversationStateError)
    # Create fresh chat and retry
    create_fresh_chat_recovery(original_message)
  else
    # Return user-friendly error
    "I encountered an issue processing your request. Please try again."
  end
end
```

### Conversation State Management
```ruby
# Maintain chat integrity
class ConversationStateManager
  def ensure_conversation_integrity!
    # Validate tool call sequences
    # Clean orphaned messages
    # Maintain proper conversation flow
  end
end
```

## Deployment & Production

### Rails 8 Production Configuration
```ruby
# config/environments/production.rb
config.active_job.queue_adapter = :solid_queue
config.solid_queue.connects_to = { database: { writing: :queue } }
config.cache_store = :solid_cache_store
config.force_ssl = true
config.assume_ssl = true
```

### Environment Variables
```bash
# Required for production
DATABASE_URL=postgresql://...
RAILS_MASTER_KEY=...
OPENAI_API_KEY=... # or ANTHROPIC_API_KEY
SMTP_USERNAME=...
SMTP_PASSWORD=...
```

## Development Workflow

### Code Review Checklist
- [ ] UUID primary keys maintained
- [ ] Proper authorization with Pundit
- [ ] N+1 query prevention
- [ ] Turbo Stream responses for real-time updates
- [ ] AI chat context properly handled
- [ ] Tests cover new functionality
- [ ] Database migrations are reversible
- [ ] Error handling implemented

### Performance Monitoring
- Monitor database query performance
- Track AI response times
- Measure Turbo Stream update latency
- Monitor background job queue health

Remember: Listopia demonstrates modern Rails 8 development with AI integration. Maintain the established patterns for authentication, real-time features, and collaborative functionality while ensuring security and performance standards.