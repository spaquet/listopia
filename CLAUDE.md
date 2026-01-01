# Claude.md - Listopia Development Guide

Quick reference for developing Listopia, a modern Rails 8 collaborative list management application.

## Stack Overview

- **Rails 8.1** with Solid Queue, Solid Cache, Solid Cable
- **Ruby 3.4.7** with UUID primary keys
- **PostgreSQL 15+** for database
- **Hotwire** (Turbo Streams + Stimulus) for real-time updates
- **Tailwind CSS 4.1** with Bun package manager
- **RubyLLM 1.8+** for AI chat integration
- **RSpec + Capybara + Factory Bot** for testing
- **Kamal + Docker** for deployment

## Architecture Patterns

### Authentication & Authorization
- Rails 8 authentication with `has_secure_password`
- Magic link tokens via `generates_token_for`
- Email verification on signup
- Pundit policies for authorization (always use `authorize @resource`)
- Rolify for role-based access control

### Database Conventions
- **All models use UUID primary keys** (never integers)
- Foreign keys are UUID type
- PostgreSQL extensions: `pgcrypto`, `plpgsql`
- Strategic indexes on common query paths
- JSONB metadata columns for flexibility

### Controller & Model Organization
- RESTful controllers with proper authorization checks
- Service objects for complex business logic (McpService, ListSharingService)
- Enums for status/priority fields
- Soft deletes with `discard` gem where needed

### Real-Time & Interactivity Philosophy
- **Prefer Turbo Streams** for all real-time updates and reactive UI
- Use Stimulus controllers only when Turbo Streams cannot solve the problem
- All UIs are responsive and mobile-first
- Respond with `turbo_stream` format from controllers
- Trigger broadcasts for multi-user real-time collaboration

### Organizations & Teams Architecture

**Foundational Model:**
- Every user belongs to one or more organizations
- Organizations auto-create on signup (personal workspace)
- Teams are optional sub-groups within organizations
- All data (lists, items, collaborations) scoped to organizations

**Three-Level Hierarchy:**
```
User → Organization → Team → Lists/Collaborators
User → Organization → Lists (without team)
```

**Role System:**
- Organization roles: member, admin, owner (stored in OrganizationMembership.role enum)
- Team roles: member, lead, admin (stored in TeamMembership.role enum)
- Use Pundit for authorization checks, Rolify for role management

**Authorization Pattern:**
Every access follows this validation chain:
1. Authentication: user must be signed in
2. Org membership: user must be member of organization
3. Role-based: Pundit policy checks specific permission
4. Query scoping: data filtered to user's organizations

Example:
```ruby
authorize @list  # Pundit checks: user in org? has permission?
@lists = policy_scope(List)  # Returns only lists in user's orgs
```

**Key Implementation Rule:**
All queries must include org context. Never fetch data without organization filter. Use either:
- `policy_scope(Model)` - Pundit handles scoping
- `current_organization.lists` - Access through association
- `.where(organization_id: current_user.organizations.select(:id))` - Explicit filter

**Reused Infrastructure:**
- Invitations table (polymorphic, add org_id column)
- Collaborators model (add org boundary validation)
- Logidze (enable on new models with has_logidze)
- CollaborationMailer (extend with org_invitation method)

## Key Models

```ruby
# User - authentication & account
has_many :lists (owner_id), :sessions, :chats, :messages, :organizations

# Organization - multi-tenant workspace
has_many :users (through memberships), :teams, :lists, :chats

# List - collaborative document
belongs_to :owner (User), :organization, :team (optional)
has_many :list_items, :list_collaborations, :list_tags
enum :status (draft, active, completed, archived)
enum :category (professional, personal)

# ListItem - tasks/content
belongs_to :list, :assigned_user (optional)
enum :priority (low, medium, high)
enum :status (pending, in_progress, completed)

# ListCollaboration - sharing & permissions
belongs_to :list, :user
enum :permission (view, comment, edit, admin)

# Chat - AI conversations
belongs_to :user, :organization, :team (optional), :focused_resource (polymorphic, optional)
has_many :messages
enum :status (active, archived, deleted)
metadata: { pending_resource_creation, pending_list_refinement, rag_enabled, model, system_prompt }

# Message - chat history
belongs_to :chat, :user (optional for assistant messages), :organization
enum :role (user, assistant, system, tool)
enum :message_type (text, templated)
attributes: { template_type, content, blocked, metadata }
```

### Organization Models

**Organization** - Top-level container
- Attributes: id (UUID), name, slug (unique), size (enum), status (enum), created_by (FK)
- Associations: has_many users (through memberships), has_many teams, has_many lists, has_many chats
- Logidze: enabled (tracks all changes)
- Used to scope all other data

**OrganizationMembership** - User-org relationship
- Attributes: organization_id (FK), user_id (FK), role (enum: member/admin/owner), status (enum: pending/active/suspended/revoked), joined_at
- Unique constraint: [organization_id, user_id]
- Tracks user's role and access status in organization

**Team** - Sub-group within organization
- Attributes: id (UUID), organization_id (FK), name, slug, created_by (FK)
- Unique constraint: [organization_id, slug]
- Associations: has_many users (through memberships), has_many lists, has_many chats
- Lists can belong to team or exist without team

**TeamMembership** - User-team relationship
- Attributes: team_id (FK), user_id (FK), organization_membership_id (FK), role (enum: member/lead/admin), joined_at
- Unique constraint: [team_id, user_id]
- Prerequisite: user must be OrganizationMembership in team's org first

## Chat System Architecture

### Overview

The chat system provides a unified conversational interface for managing lists, resources, and data. It leverages RubyLLM for AI capabilities and implements multi-layered security with OpenAI moderation and prompt injection detection.

**Core Responsibilities:**
1. Process natural language user requests
2. Detect user intent (create lists, manage resources, navigate pages, general questions)
3. Extract and validate parameters before resource creation
4. Manage multi-turn conversations with context
5. Enforce authorization and security boundaries
6. Stream real-time responses via Turbo Streams

### Command System

**Trigger Syntax:**
- `/` - Commands (instant processing, no LLM)
- `#` - List/resource references (autocomplete with search)
- `@` - User mentions (autocomplete with org boundary)

**Available Commands:**
- `/help` - Display available commands
- `/search <query>` - Global search across lists, items, comments
- `/browse [status]` - Browse lists with optional status filter
- `/clear` - Clear chat history
- `/new` - Create new chat

**Command Processing:**
- Commands are processed synchronously and return immediately
- Commands auto-clear input form on submit
- System responses use templated message format

### User Mention & Reference Autocomplete

**User Mentions (`@`):**
- Triggers on `@` character
- Searches users in current organization only
- Uses `UserFilterService` for query matching
- Displays name, email, and avatar
- Reference format: `@firstname.lastname`

**List/Item References (`#`):**
- Triggers on `#` character
- Searches lists and items in current organization
- Lists limited to accessible/owned resources
- Reference format: `#list-title` or `#item-title`
- Results include description preview (truncated)

**Parsing:**
- `ChatMentionParser` extracts and validates all mentions/references
- Metadata stored on user message for audit trail
- Invalid references are flagged but don't block message

### Message Flow Architecture

**User Input → Security Checks → Intent Detection → Processing → Response**

#### 1. Security Layer

**Prompt Injection Detection:**
```ruby
PromptInjectionDetector - detects high-risk injection attempts
├─ High Risk: Block message, log security violation
└─ Medium Risk: Allow with warning, log for monitoring
```

**Content Moderation:**
```ruby
ContentModerationService - OpenAI moderation API
├─ Filters: sexual, violence, harassment, hate_speech, self_harm
└─ Auto-archives chat if violations exceed threshold
```

**Requirements:**
- All non-command messages go through OpenAI moderation
- Blocked messages return 422 with user-friendly error
- Security logs stored in ModerationLog table

#### 2. Intent Detection

**AI Intent Router (`AiIntentRouterService`):**
Uses LLM to classify intent with high accuracy across any language/phrasing.

**Intent Types:**

| Intent | Purpose | Example |
|--------|---------|---------|
| `create_list` | Planning, learning, collections, personal goals | "Plan my business trip", "I want to become a better manager" |
| `create_resource` | Adding users, teams, orgs to the app | "Create user john@example.com", "Add team Engineering" |
| `navigate_to_page` | Redirect to existing admin/management pages | "Show me all users", "List organizations" |
| `manage_resource` | Update/delete existing resources | "Change user role", "Rename team" |
| `search_data` | Find and retrieve information | "Find lists about budget" |
| `general_question` | Casual questions, conversations | "How do I use this feature?" |

**Critical Distinction - CREATE_LIST vs CREATE_RESOURCE:**

✓ **CREATE_LIST** - Content, plans, collections:
- "Provide me with 5 books to read"
- "Create a workout routine for 8 weeks"
- "Plan a trip to Europe"
- "Help me learn Python in 6 weeks"

✓ **CREATE_RESOURCE** - Adding app infrastructure:
- "Create user john@company.com"
- "Add team called 'Design Team'"
- "Invite sarah to the organization"

#### 3. Resource Creation Flow

**Phase 1: Parameter Extraction**
```
User Message
→ ParameterExtractionService
├─ Extract available parameters
├─ Identify missing parameters
└─ Check if clarification needed (list category)
```

**Phase 2: Clarification (if needed)**
```
For Lists: Ask "Is this professional or personal?"
For Resources: Ask for specific missing parameters
│
User Response
└─ Merge new parameters with existing ones
```

**Phase 3: Creation**
```
All parameters collected
→ ChatResourceCreatorService
├─ Validates all parameters
├─ Checks authorization (user in org, can create)
└─ Creates resource + audit log
```

**Phase 4: Refinement (Lists only)**
```
List created successfully
→ ListRefinementService
├─ Analyzes list structure
├─ Generates follow-up questions
│  (e.g., "How long for this trip?", "What's your budget?")
└─ If needed: Store in chat.metadata[pending_list_refinement]
```

### Message Types & Templates

**Standard Messages:**
- `user` role: User input (text only, always stored)
- `assistant` role: LLM responses (text or templated)
- `system` role: System messages (help, errors)
- `tool` role: Tool execution results

**Templated Messages:**
Used when specialized rendering is needed (don't use for chat responses unless absolutely necessary).

Available templates: `help`, `search_results`, `browse_results`, `navigation`, `error`

**Message Blocking:**
- Messages flagged by moderation are marked `blocked: true`
- Blocked messages still visible to user as error responses
- Audit trail preserved in ModerationLog

### Authorization & Data Boundaries

**Multi-Level Access Control:**

1. **Organization Boundary:**
   - Users can only see data in their organizations
   - `Chat` belongs to `organization` → enforced at model level
   - `policy_scope(List)` returns only user's org lists

2. **Team Context (Optional):**
   - Chat can focus on a team
   - Lists can belong to teams
   - Team members only see team lists in mentions/references

3. **Mention/Reference Access:**
   - `@` mentions only show users in current organization
   - `#` references only show lists/items user has access to
   - No data leakage across organization boundaries

4. **Resource Creation Security:**
   - User must be org member to create resources
   - New resources automatically scoped to current organization
   - Collaborators validated against org membership

### Services & Components

**Core Services:**

| Service | Purpose |
|---------|---------|
| `ChatCompletionService` | Main message processing orchestrator |
| `AiIntentRouterService` | LLM-based intent classification |
| `ParameterExtractionService` | Extract & validate parameters from user input |
| `ChatResourceCreatorService` | Create users, teams, orgs, lists via chat |
| `ListRefinementService` | Generate refinement questions for new lists |
| `ListRefinementProcessorService` | Process refinement answers, apply to list |
| `ChatMentionParser` | Parse and validate @mentions and #references |
| `ContentModerationService` | OpenAI content moderation |
| `PromptInjectionDetector` | Detect prompt injection attacks |
| `LlmToolsService` | Define available tools for LLM function calling |
| `LlmToolExecutorService` | Execute LLM-requested tools |

**Controllers:**

| Controller | Purpose |
|------------|---------|
| `ChatsController` | Chat CRUD and message submission |
| `ChatMentionsController` | Autocomplete for @users and #references |

### UI/UX Patterns

**Form Handling:**
- Input clears immediately on message submit (before response)
- Enter key and Submit button have identical behavior
- Use same event handler for both (DRY principle)
- Loading indicator shown while awaiting LLM response

**Message Display:**
- User messages appear immediately
- Non-command messages show loading state, then assistant response
- Turbo Streams append messages to chat container in real-time
- Commands return responses synchronously

**Real-Time Updates:**
- Use Turbo Streams for all message appending
- Broadcast to multiple users if chat is shared (future)
- No polling - WebSocket-based via Solid Cable

**Error Messaging:**
- Human-readable errors from backend services
- If OpenAI/LLM errors occur, show friendly fallback
- Security errors never expose internal details
- All errors stored in logs for debugging

### Example Conversation Flows

**Example 1: Create a List**
```
User: "Plan a trip to Japan for 2 weeks"
→ Intent: create_list
→ Extract: title="Japan Trip", category=missing
Assistant: "Is this for work or personal use?"
User: "Personal"
→ Create list, analyze structure
Assistant: "Great! Created 'Japan Trip' list. I have a few questions:
1. When are you planning this?
2. What's your approximate budget?"
User: "July 2025, $3000"
→ Apply refinement, finalize
Assistant: "Perfect! I've added these details to your trip planning list..."
```

**Example 2: Create a User**
```
User: "Add john@company.com as a team member"
→ Intent: create_resource (type: user)
→ Extract: email, name=missing
Assistant: "I'd like to help you add john@company.com. What's their full name?"
User: "John Smith"
→ All params collected
Assistant: "Added John Smith (john@company.com) to the organization."
```

**Example 3: Navigate to Page**
```
User: "Show me all active users"
→ Intent: navigate_to_page
Assistant: "Opening the users list..." (+ navigation template)
→ Frontend redirects to /admin/users
```

### Development Standards

**Building New Chat Features:**

1. **Authorization First:**
   - Always verify user is in organization
   - Use `policy_scope` for queries
   - Never return data outside user's org

2. **Service Pattern:**
   - Create dedicated service for complex logic
   - Inherit from `ApplicationService`
   - Return `success(data: ...)` or `failure(errors: ...)`

3. **Message Creation:**
   ```ruby
   # For text responses
   Message.create_assistant(chat: @chat, content: "Response text")

   # For templated responses (rarely needed)
   Message.create_templated(chat: @chat, template_type: :help, template_data: {...})

   # For system messages
   Message.create_system(chat: @chat, content: "System notification")
   ```

4. **Intent Detection:**
   - Use `AiIntentRouterService` for flexible classification
   - Provide clear examples in service prompts
   - Never hardcode intent detection

5. **Parameter Extraction:**
   - Use `ParameterExtractionService` for user input
   - Define required vs optional parameters
   - Ask for missing parameters conversationally

6. **Error Handling:**
   - Catch exceptions, return user-friendly messages
   - Log technical errors for debugging
   - Never expose stack traces to user

### Testing Chat Features

**Key Test Scenarios:**

- Organization boundary enforcement (User A cannot see Org B data in chat)
- Intent detection accuracy (various phrasings)
- Parameter extraction and validation
- Authorization checks before creating resources
- Moderation and security blocking
- Message storage and retrieval
- Mention/reference autocomplete filtering

**Example Test:**
```ruby
it "prevents user from creating resource in different org" do
  user_a = create(:user, organization: org_a)
  user_b = create(:user, organization: org_b)
  chat = create(:chat, user: user_a, organization: org_a)

  message = Message.create_user(chat: chat, user: user_a, content: "...")
  result = ChatCompletionService.new(chat, message).call

  # Should never create resource in org_b through chat
end
```

## Frontend Approach

**Turbo-First Philosophy:** Build features with Turbo Streams and Turbo Frames whenever possible. JavaScript (via Stimulus) is a last resort for interactions that Turbo cannot handle.

- **Turbo Streams** handle real-time updates, partial replacements, and reactive UI
- **Stimulus Controllers** only for DOM interactions Turbo cannot solve (animations, complex state, third-party integrations)
- **Responsive Design** - All UIs use Tailwind's responsive utilities (mobile-first)
- **Progressive Enhancement** - Features work without JavaScript, enhanced with interactivity

### Chat UI Patterns

**Unified Chat Input:**
- Single input field for all message types (commands, mentions, regular messages)
- `@` autocomplete for user mentions
- `#` autocomplete for list/item references
- `/` command hints displayed on focus or when typing `/`

**Form Submission:**
- Enter key and Submit button trigger identical behavior
- Use same event handler to avoid duplication (DRY)
- Clear input field immediately on submit (before response)
- Show loading indicator while awaiting response

**Message Rendering:**
- User messages append to chat immediately via Turbo Stream
- Assistant messages show loading skeleton while processing
- Commands return instantly and update chat
- Use partials for consistent message styling

**Error & Success States:**
- Blocked messages display as error bubble (human-readable message)
- Success confirmations show in assistant response
- Validation errors prompt for clarification
- All error messages should be conversational, not technical

**Autocomplete Behavior:**
- Open on trigger character (`@`, `#`, `/`)
- Close on Escape or when user continues typing
- Keyboard navigation (arrow keys to select)
- Click or Enter to insert selection
- Limit results to 10 items for performance

### File Structure
```
app/
  models/           # UUID-based models with proper associations
  controllers/      # RESTful with Pundit authorization
  services/         # Complex business logic (McpService, etc)
  policies/         # Pundit authorization policies
  views/
    shared/         # Shared partials
    [resource]/     # Resource-specific templates
  javascript/
    controllers/    # Stimulus JS controllers
    
config/
  routes.rb         # RESTful routes with namespacing
  
db/
  migrate/          # Always enable pgcrypto, use UUIDs
```

### Common Tasks

**Create a model with UUID:**
```ruby
rails g model List owner:references title:string status:string
# Modify migration: id: :uuid, foreign_key: { type: :uuid }
```

**Add authorization:**
```ruby
# In controller: before_action :authorize_list_access!
# Create app/policies/list_policy.rb with show?, edit?, destroy? methods
authorize @list  # Use Pundit for every action
```

**Real-time update (Turbo Stream - preferred):**
```erb
<%= turbo_stream.replace(@list) do %>
  <%= render "list", list: @list %>
<% end %>
```

**Complex interaction (Stimulus - use only when needed):**
```javascript
// app/javascript/controllers/dropdown_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["menu"]
  
  toggle() {
    this.menuTarget.classList.toggle("hidden")
  }
}
```

**Responsive design (Tailwind - always):**
```erb
<div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
  <div class="p-4 bg-white rounded-lg">Mobile-first responsive</div>
</div>
```

### Organization & Team Operations

**Check if user is in organization:**
```ruby
current_user.in_organization?(org)  # true/false
```

**Get all accessible lists:**
```ruby
policy_scope(List)  # Lists in all user's orgs
current_organization.lists  # Lists in current org
```

**Get teams in current org:**
```ruby
current_organization.teams
current_user.teams.where(organization_id: current_organization.id)
```

**Create resource in current org:**
```ruby
@list = current_organization.lists.build(title: "...")
@list.owner = current_user
authorize @list
```

**Invite user to organization:**
Use OrganizationInvitationService (see workflows section)

**Ensure org boundary in queries:**
All custom queries should include:
```ruby
.where(organization_id: current_user.organizations.select(:id))
```

## Performance & Quality

### Database
- Use `includes`, `joins`, `preload` to prevent N+1 queries
- Index foreign keys and frequently queried columns
- Pagination with Pagy for large datasets
- Cache expensive operations with Solid Cache

### Code Quality
- RuboCop Omakase enforces style
- Brakeman checks for security issues
- Bullet gem prevents N+1 queries in development
- Keep controllers thin, push logic to models/services

### Testing
- Model specs for validations & associations
- Controller specs for authorization & responses
- Integration/system specs for user workflows
- Use Factory Bot for test data, Faker for random values

## Common Issues & Solutions

**N+1 Queries:** Use `includes` when loading associations  
**Authorization Failed:** Always call `authorize` after loading resource  
**UUID Errors:** Ensure migration uses `id: :uuid` and `type: :uuid` for FKs  
**Turbo Stream Not Working:** Check format responds with `format.turbo_stream`  
**Test Database Issues:** Run `RAILS_ENV=test rails db:reset`

## Development Standards
### Organization & Team Development Guidelines

**Query Scoping Checklist:**
When fetching any data, ensure:
- [ ] Query includes org boundary check
- [ ] Using policy_scope when loading multiple records
- [ ] Explicit .where(organization_id: ...) if not using policy_scope
- [ ] Accessed through association (current_organization.items) when possible

**Creating Resources in Org Context:**
- Set organization_id when creating records
- Use: `current_organization.lists.build(...)` OR `@resource.organization_id = current_organization.id`
- Verify organization_id is persisted in database

**Model Validation for Org Boundaries:**
Add validation when model references resource in different org:
- Collaborator must validate user is in resource's org
- TeamMembership must validate user is org member
- Any cross-org references need validation

**Authorization Pattern for Controllers:**
Every action accessing org/team data:
- Call `authorize @resource` (Pundit)
- OR verify `current_user.in_organization?(org)` explicitly
- Always check policy before responding

**Testing Organization Access Control:**
Core test scenario:
- User in Org A cannot access data in Org B
- Both positive (authorized) and negative (denied) cases
- Test at multiple layers: policy, controller, query

## Useful Commands

```bash
# Database
rails db:create db:migrate       # Setup dev database
RAILS_ENV=test rails db:reset   # Reset test database

# Testing
bundle exec rspec               # Run all tests
bundle exec rspec spec/models   # Run model tests only

# Code Quality
bundle exec rubocop --fix       # Auto-fix style issues
bundle exec brakeman            # Security check

# Create Simulus controller
rails g stimulus [NameOfTheController] # Create a new stimulus controller and add it to the index.js

# Frontend
bun install                      # Install JS dependencies
bun run build:css               # Compile Tailwind

# Deployment
kamal setup                      # Initial deployment
kamal deploy                     # Deploy changes
```

## External Resources

- [Rails 8 Guides](https://guides.rubyonrails.org/)
- [Hotwire Documentation](https://hotwired.dev/)
- [Pundit Authorization](https://github.com/varvet/pundit)
- [RSpec Rails](https://github.com/rspec/rspec-rails)
