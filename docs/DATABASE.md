# Listopia Database Design Documentation

## Supported Database Scenarios

### **User Management**
1. **User registration and authentication** - Store user credentials, email verification, and session data
2. **User profiles and preferences** - Personal information, notification settings, and app preferences
3. **Multi-database configuration** - Separate databases for cache, queue, and cable in production

### **List Management**
4. **List creation and ownership** - Users create and own lists with metadata
5. **List status lifecycle** - Draft → Active → Completed → Archived progression
6. **Public list sharing** - Generate secure URLs for public access
7. **List categorization** - Color themes and organizational metadata

### **Collaboration System**
8. **User collaboration** - Many-to-many relationships with permission levels
9. **Invitation management** - Pending invitations for unregistered users
10. **Permission levels** - Read-only vs full collaboration access

### **Item Management**
11. **Flexible item types** - Tasks, goals, milestones, notes, and more
12. **Item organization** - Priority levels, due dates, and positioning
13. **Assignment system** - Assign items to specific collaborators
14. **Completion tracking** - Mark items complete with timestamps

### **Notification System**
15. **Notification preferences** - Per-user settings for delivery channels and types
16. **Notification delivery** - Database storage for in-app notifications via Noticed gem

### **Performance & Scalability**
17. **UUID primary keys** - Enhanced security and distributed system support
18. **Optimized indexing** - Performance indexes for common query patterns
19. **PostgreSQL features** - JSON columns, advanced indexing, and constraints

## Overview

Listopia uses **PostgreSQL** as its primary database with **UUID primary keys** throughout for enhanced security and scalability. The design follows Rails conventions while leveraging PostgreSQL-specific features for optimal performance.

## Architecture

### Database Strategy

- **Primary Database** - Main application data (users, lists, items, collaborations)
- **Cache Database** - Rails cache storage via Solid Cache
- **Queue Database** - Background job storage via Solid Queue  
- **Cable Database** - Action Cable WebSocket data via Solid Cable

### UUID Primary Key Strategy

```ruby
# All models use UUID primary keys
id: :uuid, not null, primary key

# Benefits:
# - Enhanced security (no sequential ID exposure)
# - Distributed system compatibility
# - Merge-friendly (no ID conflicts)
# - Better for public URLs
```

## Core Models & Relationships

### User Model

```ruby
# == Schema Information
# Table name: users
#
#  id                       :uuid             not null, primary key
#  avatar_url               :string
#  bio                      :text
#  email                    :string           not null
#  email_verification_token :string
#  email_verified_at        :datetime
#  name                     :string           not null
#  password_digest          :string           not null
#  provider                 :string
#  uid                      :string
#  created_at               :datetime         not null
#  updated_at               :datetime         not null

class User < ApplicationRecord
  # Authentication
  has_secure_password
  generates_token_for :magic_link, expires_in: 15.minutes
  generates_token_for :email_verification, expires_in: 24.hours

  # Core associations
  has_many :lists, dependent: :destroy
  has_many :list_collaborations, dependent: :destroy
  has_many :collaborated_lists, through: :list_collaborations, source: :list
  has_one :notification_settings, dependent: :destroy

  # Notification system
  has_many :notifications, as: :recipient, dependent: :destroy, class_name: "Noticed::Notification"
end
```

### List Model

```ruby
# == Schema Information
# Table name: lists
#
#  id          :uuid             not null, primary key
#  color_theme :string           default("blue")
#  description :text
#  is_public   :boolean          default(FALSE)
#  metadata    :json
#  public_slug :string
#  status      :integer          default("draft"), not null
#  title       :string           not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  user_id     :uuid             not null

class List < ApplicationRecord
  belongs_to :owner, class_name: "User", foreign_key: "user_id"
  has_many :list_items, dependent: :destroy
  has_many :list_collaborations, dependent: :destroy
  has_many :collaborators, through: :list_collaborations, source: :user

  # Status enum (Rails-only, not PostgreSQL enum)
  enum :status, {
    draft: 0,
    active: 1, 
    completed: 2,
    archived: 3
  }, prefix: true
end
```

### ListItem Model

```ruby
# == Schema Information
# Table name: list_items
#
#  id               :uuid             not null, primary key
#  completed        :boolean          default(FALSE)
#  completed_at     :datetime
#  description      :text
#  due_date         :datetime
#  item_type        :integer          default("task"), not null
#  metadata         :json
#  position         :integer          default(0)
#  priority         :integer          default("medium"), not null
#  reminder_at      :datetime
#  title            :string           not null
#  url              :string
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  assigned_user_id :uuid
#  list_id          :uuid             not null

class ListItem < ApplicationRecord
  belongs_to :list
  belongs_to :assigned_user, class_name: "User", optional: true

  # Item type enum - supports multiple content types
  enum :item_type, {
    # Core Planning Types
    task: 0,          # Basic actionable item
    goal: 1,          # Objectives and targets
    milestone: 2,     # Key deadlines and achievements
    action_item: 3,   # Specific actions from meetings
    waiting_for: 4,   # Items waiting on others
    
    # Content Types
    note: 5,          # Information and documentation
    link: 6,          # Web links and resources
    file: 7,          # File attachments
    reminder: 8,      # Time-based reminders
    idea: 9           # Ideas and inspiration
  }, prefix: true

  # Priority enum
  enum :priority, {
    low: 0,
    medium: 1,
    high: 2,
    urgent: 3
  }, prefix: true
end
```

### ListCollaboration Model

```ruby
# == Schema Information
# Table name: list_collaborations
#
#  id                     :uuid             not null, primary key
#  email                  :string
#  invitation_accepted_at :datetime
#  invitation_sent_at     :datetime
#  invitation_token       :string
#  permission             :integer          default("read"), not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  invited_by_id          :uuid
#  list_id                :uuid             not null
#  user_id                :uuid

class ListCollaboration < ApplicationRecord
  belongs_to :list
  belongs_to :user, optional: true  # Optional for pending invitations
  belongs_to :invited_by, class_name: "User", optional: true

  # Permission levels
  enum :permission, {
    read: 0,        # View-only access
    collaborate: 1  # Full edit access
  }, prefix: true

  # Rails 8 token generation for invitations
  generates_token_for :invitation, expires_in: 24.hours
end
```

### NotificationSettings Model

```ruby
# == Schema Information
# Table name: notification_settings
#
#  id                            :uuid             not null, primary key
#  email_notifications           :boolean          default(TRUE), not null
#  sms_notifications             :boolean          default(FALSE), not null  
#  push_notifications            :boolean          default(TRUE), not null
#  collaboration_notifications   :boolean          default(TRUE), not null
#  list_activity_notifications   :boolean          default(TRUE), not null
#  item_activity_notifications   :boolean          default(TRUE), not null
#  status_change_notifications   :boolean          default(TRUE), not null
#  notification_frequency        :string           default("immediate"), not null
#  quiet_hours_start             :time
#  quiet_hours_end               :time
#  timezone                      :string           default("UTC")
#  created_at                    :datetime         not null
#  updated_at                    :datetime         not null
#  user_id                       :uuid             not null

class NotificationSetting < ApplicationRecord
  belongs_to :user

  validates :notification_frequency, 
    inclusion: { in: %w[immediate daily_digest weekly_digest disabled] }
  validates :timezone, presence: true
end
```

## Database Configuration

### Multi-Database Setup

```yaml
# config/database.yml
production:
  primary: &primary_production
    <<: *default
    database: listopia_production
    username: listopia
    password: <%= ENV["LISTOPIA_DATABASE_PASSWORD"] %>
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

### PostgreSQL Extensions

```ruby
# Enable UUID generation
enable_extension "pgcrypto"

# Future extensions for advanced features
# enable_extension "pg_trgm"    # For fuzzy text search
# enable_extension "unaccent"   # For accent-insensitive search
```

## Indexing Strategy

### Performance Indexes

```ruby
# User indexes
add_index :users, :email, unique: true
add_index :users, :email_verification_token, unique: true
add_index :users, [:provider, :uid], unique: true

# List indexes - optimized for common queries
add_index :lists, :user_id
add_index :lists, :created_at
add_index :lists, :status
add_index :lists, :is_public
add_index :lists, :public_slug, unique: true
add_index :lists, [:user_id, :status]
add_index :lists, [:user_id, :created_at]

# List item indexes - supports sorting and filtering
add_index :list_items, :list_id
add_index :list_items, :assigned_user_id
add_index :list_items, :completed
add_index :list_items, :due_date
add_index :list_items, :item_type
add_index :list_items, :priority
add_index :list_items, :position
add_index :list_items, :created_at
add_index :list_items, [:list_id, :completed]
add_index :list_items, [:list_id, :priority]
add_index :list_items, [:due_date, :completed]
add_index :list_items, [:assigned_user_id, :completed]

# Collaboration indexes - supports permission queries
add_index :list_collaborations, :list_id
add_index :list_collaborations, :user_id
add_index :list_collaborations, :email
add_index :list_collaborations, :permission
add_index :list_collaborations, :invitation_token, unique: true
add_index :list_collaborations, [:list_id, :user_id], unique: true, where: "user_id IS NOT NULL"
add_index :list_collaborations, [:list_id, :email], unique: true, where: "email IS NOT NULL"
add_index :list_collaborations, [:user_id, :permission]

# Notification settings
add_index :notification_settings, :user_id, unique: true
add_index :notification_settings, :notification_frequency
```

### Query Optimization Patterns

```ruby
# Efficient list loading with associations
lists = current_user.lists
                   .includes(:list_items, :collaborators)
                   .where(status: :active)
                   .order(created_at: :desc)

# Optimized collaboration queries
accessible_lists = List.joins("LEFT JOIN list_collaborations ON lists.id = list_collaborations.list_id")
                      .where("lists.user_id = ? OR list_collaborations.user_id = ?", user.id, user.id)
                      .distinct

# Efficient item filtering
items = list.list_items
            .includes(:assigned_user)
            .where(completed: false)
            .order(:priority, :due_date)
```

## Data Validation & Constraints

### Database Constraints

```ruby
# Foreign key constraints for data integrity
add_foreign_key :lists, :users
add_foreign_key :list_items, :lists
add_foreign_key :list_items, :users, column: :assigned_user_id
add_foreign_key :list_collaborations, :lists
add_foreign_key :list_collaborations, :users
add_foreign_key :list_collaborations, :users, column: :invited_by_id
add_foreign_key :notification_settings, :users

# Unique constraints
add_index :users, :email, unique: true
add_index :lists, :public_slug, unique: true
add_index :list_collaborations, :invitation_token, unique: true

# Conditional unique constraints
add_index :list_collaborations, [:list_id, :user_id], unique: true, where: "user_id IS NOT NULL"
add_index :list_collaborations, [:list_id, :email], unique: true, where: "email IS NOT NULL"
```

### Model Validations

```ruby
# User validations
validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
validates :name, presence: true

# List validations  
validates :title, presence: true, length: { maximum: 255 }
validates :description, length: { maximum: 1000 }
validates :status, presence: true

# ListItem validations
validates :title, presence: true, length: { maximum: 255 }
validates :description, length: { maximum: 1000 }
validates :item_type, presence: true
validates :priority, presence: true

# ListCollaboration validations
validates :email, presence: true, unless: :user_id?
validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
validates :permission, presence: true
validates :user_id, uniqueness: { scope: :list_id }, allow_nil: true
validates :email, uniqueness: { scope: :list_id }, allow_nil: true
```

## JSON Metadata Usage

### Flexible Metadata Storage

```ruby
# Lists metadata examples
{
  "tags": ["work", "urgent"],
  "template_used": "project-checklist",
  "custom_fields": {
    "budget": 5000,
    "deadline": "2024-12-31"
  },
  "ui_preferences": {
    "collapsed_sections": ["completed"],
    "sort_preference": "priority"
  }
}

# ListItems metadata examples  
{
  "file_attachments": [
    {"name": "document.pdf", "url": "...", "size": 1024000}
  ],
  "time_tracking": {
    "estimated_hours": 4,
    "actual_hours": 3.5
  },
  "custom_properties": {
    "client": "Acme Corp",
    "billable": true
  }
}
```

### JSON Query Examples

```ruby
# Find lists with specific tags
List.where("metadata->>'tags' ? :tag", tag: "urgent")

# Find items with file attachments
ListItem.where("metadata->'file_attachments' IS NOT NULL")

# Filter by custom properties
ListItem.where("metadata->'custom_properties'->>'billable' = 'true'")
```

## Migration Patterns

### UUID Migration Pattern

```ruby
class CreateLists < ActiveRecord::Migration[8.0]
  def change
    create_table :lists, id: :uuid do |t|
      t.string :title, null: false
      t.text :description
      t.integer :status, default: 0, null: false
      t.boolean :is_public, default: false
      t.string :public_slug
      t.string :color_theme, default: "blue"
      t.json :metadata
      t.references :user, null: false, foreign_key: true, type: :uuid

      t.timestamps
    end

    add_index :lists, :user_id
    add_index :lists, :status
    add_index :lists, :is_public
    add_index :lists, :public_slug, unique: true
    add_index :lists, [:user_id, :status]
  end
end
```

### Adding Indexes Migration

```ruby
class AddPerformanceIndexes < ActiveRecord::Migration[8.0]
  def change
    # Composite indexes for common query patterns
    add_index :list_items, [:list_id, :completed]
    add_index :list_items, [:due_date, :completed]
    add_index :list_items, [:assigned_user_id, :completed]
    
    # Ensure foreign key constraints
    add_foreign_key :list_items, :users, column: :assigned_user_id
  end
end
```

## Query Optimization

### N+1 Query Prevention

```ruby
# Bad: N+1 queries
lists = current_user.lists
lists.each do |list|
  puts list.list_items.count  # N+1 query
  puts list.collaborators.map(&:name)  # N+1 query
end

# Good: Eager loading
lists = current_user.lists
                   .includes(:list_items, :collaborators)
lists.each do |list|
  puts list.list_items.size  # No additional query
  puts list.collaborators.map(&:name)  # No additional query
end
```

### Complex Queries

```ruby
# Find lists accessible to user with item counts
accessible_lists = List.joins(
  "LEFT JOIN list_collaborations ON lists.id = list_collaborations.list_id"
).joins(
  "LEFT JOIN list_items ON lists.id = list_items.list_id"
).where(
  "lists.user_id = ? OR list_collaborations.user_id = ?", user.id, user.id
).group(
  "lists.id"
).select(
  "lists.*, COUNT(list_items.id) as items_count"
).distinct

# Find overdue items across all accessible lists
overdue_items = ListItem.joins(:list)
                        .joins("LEFT JOIN list_collaborations ON lists.id = list_collaborations.list_id")
                        .where("lists.user_id = ? OR list_collaborations.user_id = ?", user.id, user.id)
                        .where("due_date < ? AND completed = false", Time.current)
                        .includes(:list, :assigned_user)
```

### Database Functions

```ruby
# Custom PostgreSQL functions for complex operations
def up
  execute <<-SQL
    CREATE OR REPLACE FUNCTION calculate_list_progress(list_uuid UUID)
    RETURNS DECIMAL AS $
    DECLARE
      total_items INTEGER;
      completed_items INTEGER;
    BEGIN
      SELECT COUNT(*) INTO total_items 
      FROM list_items 
      WHERE list_id = list_uuid;
      
      SELECT COUNT(*) INTO completed_items 
      FROM list_items 
      WHERE list_id = list_uuid AND completed = true;
      
      IF total_items = 0 THEN
        RETURN 0;
      ELSE
        RETURN (completed_items::DECIMAL / total_items * 100);
      END IF;
    END;
    $ LANGUAGE plpgsql;
  SQL
end
```

## Backup & Maintenance

### Backup Strategy

```bash
# Full database backup
pg_dump -h localhost -U postgres -W -F c listopia_production > backup_$(date +%Y%m%d_%H%M%S).dump

# Schema-only backup
pg_dump -h localhost -U postgres -W -s listopia_production > schema_backup.sql

# Data-only backup
pg_dump -h localhost -U postgres -W -a listopia_production > data_backup.sql

# Restore from backup
pg_restore -h localhost -U postgres -W -d listopia_production backup_20241201_120000.dump
```

### Maintenance Tasks

```ruby
# Rails maintenance tasks
namespace :db do
  desc "Clean up expired tokens"
  task cleanup_expired_tokens: :environment do
    # Rails 8 tokens are automatically validated for expiration
    # But clean up any legacy token fields if needed
    User.where("email_verification_token IS NOT NULL AND email_verified_at IS NOT NULL")
        .update_all(email_verification_token: nil)
  end

  desc "Update list statistics"
  task update_list_stats: :environment do
    List.find_each do |list|
      total = list.list_items.count
      completed = list.list_items.where(completed: true).count
      
      # Update metadata with current stats
      list.update(
        metadata: list.metadata.merge({
          "stats" => {
            "total_items" => total,
            "completed_items" => completed,
            "completion_percentage" => total > 0 ? (completed.to_f / total * 100).round(2) : 0,
            "last_updated" => Time.current.iso8601
          }
        })
      )
    end
  end
end
```

## Testing Database

### Test Database Setup

```ruby
# spec/rails_helper.rb
RSpec.configure do |config|
  config.use_transactional_fixtures = true
  
  # Database cleaner configuration
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

### Factory Patterns

```ruby
# spec/factories/users.rb
FactoryBot.define do
  factory :user do
    sequence(:name) { |n| "User #{n}" }
    sequence(:email) { |n| "user#{n}@example.com" }
    password { "password123" }
    
    trait :verified do
      email_verified_at { Time.current }
    end
  end
end

# spec/factories/lists.rb  
FactoryBot.define do
  factory :list do
    title { "Test List" }
    description { "A test list for specs" }
    status { :active }
    color_theme { "blue" }
    
    association :owner, factory: :user, strategy: :create
    
    trait :with_items do
      after(:create) do |list|
        create_list(:list_item, 3, list: list)
      end
    end
    
    trait :public do
      is_public { true }
      public_slug { SecureRandom.urlsafe_base64(8) }
    end
  end
end
```

### Database Test Helpers

```ruby
# spec/support/database_helpers.rb
module DatabaseHelpers
  def with_database_connection
    ActiveRecord::Base.connection.transaction do
      yield
      raise ActiveRecord::Rollback
    end
  end

  def count_queries(&block)
    count = 0
    callback = lambda { |*| count += 1 }
    
    ActiveSupport::Notifications.subscribed(callback, "sql.active_record") do
      yield
    end
    
    count
  end
end
```

## Performance Monitoring

### Database Monitoring

```ruby
# Monitor slow queries in development
if Rails.env.development?
  ActiveSupport::Notifications.subscribe("sql.active_record") do |name, start, finish, id, payload|
    duration = finish - start
    if duration > 100.ms
      Rails.logger.warn "Slow Query (#{duration.round(2)}s): #{payload[:sql]}"
    end
  end
end
```

### Query Analysis

```sql
-- Find most expensive queries
SELECT query, calls, total_time, mean_time
FROM pg_stat_statements
ORDER BY total_time DESC
LIMIT 10;

-- Check index usage
SELECT schemaname, tablename, attname, n_distinct, correlation
FROM pg_stats
WHERE tablename = 'lists';

-- Analyze table statistics
ANALYZE lists;
EXPLAIN ANALYZE SELECT * FROM lists WHERE user_id = 'uuid-here';
```

## Security Considerations

### Data Protection

```ruby
# Sensitive data handling
class User < ApplicationRecord
  # Never log password_digest
  def inspect
    super.sub(/, password_digest: "[FILTERED]"/, "")
  end
  
  # Secure token generation
  def generate_secure_token(purpose)
    SecureRandom.urlsafe_base64(32)
  end
end
```

### Database Security

```sql
-- Production database security
-- Create dedicated application user
CREATE USER listopia_app WITH PASSWORD 'secure_password';

-- Grant minimal required permissions
GRANT CONNECT ON DATABASE listopia_production TO listopia_app;
GRANT USAGE ON SCHEMA public TO listopia_app;
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public TO listopia_app;
GRANT USAGE ON ALL SEQUENCES IN SCHEMA public TO listopia_app;

-- Revoke dangerous permissions
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE ALL ON DATABASE listopia_production FROM PUBLIC;
```

## Troubleshooting

### Common Issues

**1. UUID Generation Problems**
```ruby
# Ensure pgcrypto extension is enabled
enable_extension "pgcrypto"

# Check UUID generation
User.connection.execute("SELECT gen_random_uuid();")
```

**2. Slow Queries**
```sql
-- Check missing indexes
SELECT schemaname, tablename, attname, n_distinct, correlation
FROM pg_stats  
WHERE schemaname = 'public' AND n_distinct > 100;

-- Check query performance
EXPLAIN (ANALYZE, BUFFERS) SELECT * FROM lists WHERE status = 1;
```

**3. Foreign Key Violations**
```ruby
# Check referential integrity
List.joins("LEFT JOIN users ON lists.user_id = users.id")
    .where("users.id IS NULL")
    .count

# Fix orphaned records
List.where.not(user_id: User.select(:id)).delete_all
```

**4. Migration Issues**
```bash
# Reset database in development
rails db:drop db:create db:migrate db:seed

# Check migration status
rails db:migrate:status

# Rollback specific migration
rails db:rollback STEP=1
```

### Database Debugging

```ruby
# Enable query logging
ActiveRecord::Base.logger = Logger.new(STDOUT)

# Check connection status
ActiveRecord::Base.connection.active?

# Analyze query performance
result = ActiveRecord::Base.connection.execute("
  EXPLAIN (ANALYZE, BUFFERS, FORMAT JSON) 
  SELECT * FROM lists WHERE user_id = '#{user.id}'
")
puts JSON.pretty_generate(result.first)
```

## Future Enhancements

### Planned Database Features

1. **Full-text search** - PostgreSQL's built-in search capabilities
2. **Partitioning** - Table partitioning for large datasets
3. **Read replicas** - Separate read-only database instances
4. **Advanced indexing** - GIN indexes for JSON queries
5. **Materialized views** - Pre-computed aggregate data

### Scalability Considerations

```ruby
# Future: Database sharding preparation
class ApplicationRecord < ActiveRecord::Base
  self.abstract_class = true
  
  # Future: Shard by user_id
  def self.shard_key
    :user_id
  end
end

# Future: Connection pool optimization
Rails.application.configure do
  config.database_configuration[Rails.env]["pool"] = ENV.fetch("DB_POOL_SIZE", 5).to_i
  config.database_configuration[Rails.env]["checkout_timeout"] = 10
end
```

## Summary

Listopia's database design provides a solid foundation for a collaborative list management application with:

**Key Strengths:**
- **UUID primary keys** - Enhanced security and scalability
- **PostgreSQL features** - JSON columns, advanced indexing, constraints
- **Optimized performance** - Strategic indexing for common query patterns
- **Data integrity** - Foreign key constraints and comprehensive validations
- **Flexible metadata** - JSON columns for extensible data storage
- **Multi-database support** - Separate databases for cache, queue, and cable

**Performance Features:**
- **Efficient associations** - Proper eager loading patterns
- **Query optimization** - Indexed columns for common searches
- **Scalable design** - Ready for horizontal scaling with UUID keys

The design balances Rails conventions with PostgreSQL-specific optimizations to create a robust, performant data layer that can grow with the application's needs.