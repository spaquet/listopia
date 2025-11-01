# Database Architecture

Listopia uses PostgreSQL with UUID primary keys throughout. All model schema information is documented via the Annotate gem directly in model files—refer to those for detailed field definitions, indexes, and constraints.

## Design Principles

- **UUID Primary Keys** - Every table uses UUID primary keys for security and distributed system readiness
- **PostgreSQL Features** - Leverages JSON/JSONB columns, advanced indexing, and constraints
- **Solid Stack** - Separate databases for cache, queue, and cable operations
- **Data Integrity** - Foreign key constraints and comprehensive model validations

## Core Models

Detailed schema documentation is in each model file's `== Schema Information` block (via Annotate gem):

### Authentication & Users
- **[User](../app/models/user.rb)** - User accounts with email verification and passwordless auth
- **[Session](../app/models/session.rb)** - Session tokens with expiration tracking

### Lists & Collaboration
- **[List](../app/models/list.rb)** - Main document/list container with status tracking
- **[ListItem](../app/models/list_item.rb)** - Tasks, items within lists with priority/due dates
- **[ListCollaboration](../app/models/list_collaboration.rb)** - Sharing permissions and collaborator management
- **[Invitation](../app/models/invitation.rb)** - Email-based collaboration invitations with tokens

### AI & Chat
- **[Chat](../app/models/chat.rb)** - Conversation containers with context snapshots
- **[Message](../app/models/message.rb)** - Messages with role tracking, tokens used, and tool calls
- **[Model](../app/models/model.rb)** - LLM model metadata (via Ruby LLM integration)
- **[ToolCall](../app/models/tool_call.rb)** - AI tool invocations (for creating/updating lists)

### Supporting Models
- **[Role](../app/models/role.rb)** - User roles for Rolify authorization system
- **[Tag](../app/models/tag.rb)** - Tagging system for organizing lists and items
- **[NotificationSetting](../app/models/notification_setting.rb)** - User notification preferences
- **[Relationship](../app/models/relationship.rb)** - Polymorphic relationships (hierarchies, dependencies)

## Key Relationships

### User Account
```
User
  ├── has_many :lists (owner)
  ├── has_many :list_collaborations (collaborator)
  ├── has_many :collaborated_lists (through collaborations)
  ├── has_many :chats
  ├── has_many :messages (user-created)
  ├── has_one :notification_settings
  └── has_and_belongs_to_many :roles (Rolify)
```

### List Collaboration
```
List
  ├── belongs_to :owner (User)
  ├── has_many :list_items
  ├── has_many :list_collaborations
  ├── has_many :collaborators (through list_collaborations)
  ├── has_many :invitations
  ├── belongs_to :parent_list (optional, for hierarchies)
  └── has_many :sub_lists
```

### Chat System
```
Chat
  ├── belongs_to :user
  ├── belongs_to :model (optional, for LLM metadata)
  └── has_many :messages
    ├── Message
    │   ├── belongs_to :chat
    │   ├── belongs_to :user (optional, nil for assistant)
    │   └── has_many :tool_calls
```

## Query Patterns

### Finding Accessible Lists
```ruby
# Lists a user can access (owned or collaborated)
user.lists + user.collaborated_lists
# Or use the scope
List.accessible_by(user)
```

### Chat History with Context
```ruby
# Load chat with full message history
chat = Chat.includes(:messages).find(id)

# Filter conversation messages (no tool messages)
chat.messages.conversation.order(:created_at)

# Get tool calls for debugging
chat.messages.where(role: :tool)
```

### List Item Status Filtering
```ruby
# Common queries
list.list_items.status_pending
list.list_items.status_completed
list.list_items.where.not(assigned_user_id: nil)
```

## Database Configuration

Listopia uses multiple databases via Solid Stack:

```yaml
production:
  primary: &primary_production
    database: listopia_production
  cache:
    <<: *primary_production
    database: listopia_production_cache
    migrations_paths: db/cache_migrate
  queue:
    <<: *primary_production
    database: listopia_production_queue
    migrations_paths: db/queue_migrate
  cable:
    <<: *primary_production
    database: listopia_production_cable
    migrations_paths: db/cable_migrate
```

## Enums

Models use PostgreSQL enums (as Rails enums) for state tracking:

- **List.status** - draft, active, completed, archived
- **ListItem.status** - pending, in_progress, completed
- **ListItem.priority** - low, medium, high
- **ListCollaboration.permission** - view, comment, edit, admin
- **Chat.status** - active, archived, completed, workflow_planning, error
- **Message.role** - user, assistant, system, tool
- **User.status** - active, suspended, deactivated

## Indexing Strategy

Strategic indexes are created for common query patterns:

```ruby
# Foreign key indexes (automatic)
index :user_id
index :chat_id
index :list_id

# Composite indexes for common filters
index [:user_id, :status]
index [:chat_id, :role]
index [:chat_id, :created_at]

# Unique constraints where appropriate
index :email, unique: true
index :session_token, unique: true
```

See migrations in `db/migrate/` for complete indexing strategy.

## JSON Metadata Columns

Many models include `metadata` JSON field for flexible extension:

```ruby
# Examples
list.metadata = { tags: ["work", "urgent"], custom_field: "value" }
message.context_snapshot = { list_id: "...", list_title: "...", user_permissions: {...} }
chat.context = { page: "lists#show", selected_list_id: "..." }
```

## Migrations

Run migrations with:

```bash
# Create databases
rails db:create

# Run all migrations
rails db:migrate

# For specific databases
rails db:migrate:cache
rails db:migrate:queue
rails db:migrate:cable

# Rollback
rails db:rollback STEP=1
```

## Audit Trail & Change History

Listopia uses **[Logidze](https://github.com/palkan/logidze)** for comprehensive audit logging and temporal queries. This provides a complete change history without additional tables per model.

### How Logidze Works

Logidze stores changes as a JSON log in the `logidze_data` table and automatically triggers PostgreSQL functions to record mutations:

```ruby
# Add to any model to track changes
class List < ApplicationRecord
  has_logidze
end
```

### Accessing Change History

```ruby
# Get all changes to a list
list.log_data.map { |v| v.version }

# Get specific version at a point in time
list_v1 = list.at(2.days.ago)

# Compare current vs historical
list.changes_from(1.day.ago)

# View who changed what
list.log_data.diff  # JSON of all diffs
```

### Temporal Queries

```ruby
# Find lists as they existed 3 days ago
List.at(3.days.ago)

# Get audit information
list.logidze_audit_log
```

### Audited Models

Models with `has_logidze` are tracked:
- **List** - Track title, description, status changes
- **ListItem** - Track item status, assignments, priority changes
- **Chat** - Track conversation state and context updates

### Schema Considerations

- Uses SQL format (`config.active_record.schema_format = :sql`) to preserve database functions and triggers
- Logidze data stored in `logidze_data` table with JSONB log_data
- Minimal performance overhead with async cleanup

## Performance Notes

- **Eager loading** - Always use `.includes()` to avoid N+1 queries
- **Pagination** - Use `pagy` gem for efficient list pagination
- **Full-text search** - `pg_search` gem for PostgreSQL search capabilities
- **Soft deletes** - `discard` gem for recoverable deletions
- **Audit trail** - `logidze` gem tracks all changes with temporal queries and complete change history