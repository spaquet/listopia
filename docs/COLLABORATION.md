# Listopia Collaboration Feature - Detailed Architecture

## Executive Summary

This document outlines a comprehensive architecture for enabling collaboration on Lists and ListItems in Listopia. The design leverages existing patterns (admin user invitation flow) and extends them to support user-to-user collaboration with granular permissions and role-based access control.

---

## 1. Core Concepts & Terminology

### 1.1 Collaboration Types
- **List Collaboration**: Users collaborate on an entire list, seeing all items and being able to edit based on permissions
- **ListItem Collaboration**: Users collaborate on specific items within a list (e.g., task assignment with delegation rights)

### 1.2 User Types
- **Owner**: Creator of the resource (List/ListItem)
- **Collaborator**: User with explicit permissions on a resource
- **Invitee**: User who has been invited but hasn't accepted yet
- **Registered User**: Existing Listopia user
- **Unregistered User**: Email-based invitee who needs to create an account

### 1.3 Permission Levels

We use a two-tier permission system with role-based extensions via Rolify:

- **`read` (0)**: View-only access
  - View list/items and collaborator information
  - Cannot create, edit, delete, or modify items

- **`write` (1)**: Full collaboration access
  - Everything in Read + create/edit/complete/delete items
  - Can assign items to other users
  - **Can invite other collaborators** (important for delegation)
  - Cannot change permissions or remove other collaborators

For ListItem-level collaboration, `write` permission enables:
- Full responsibility for item execution
- Ability to sub-assign or delegate to team members (if `can_invite_collaborators` role assigned)
- Distinction between "manager" (list owner) and "executor" (item collaborator)

#### Role-Based Extensions

Using Rolify, we define additional roles on the Collaborator model:
- **`can_invite_collaborators`**: Can invite/add other users to collaborate (even with read-only access)
- **`can_manage_permissions`**: Can change other collaborators' permissions (reserved for owner/admin)
- **`can_remove_collaborators`**: Can remove other collaborators (reserved for owner/admin)

This enables use cases like:
- Manager assigns task (ListItem) to team lead with `write` + `can_invite_collaborators` role
- Team lead can sub-assign to team members without requiring manager intervention

---

## 2. Database Architecture

### 2.1 Existing Tables

#### `collaborators` table
```ruby
{
  id: uuid (PK)
  collaboratable_type: string (polymorphic: "List" or "ListItem")
  collaboratable_id: uuid (polymorphic foreign key)
  user_id: uuid (FK to users, NOT NULL)
  permission: integer (0=read, 1=write)
  created_at: timestamp
  updated_at: timestamp
}

# Indexes
- UNIQUE: (collaboratable_id, collaboratable_type, user_id)
- Regular: (user_id)
- Polymorphic: (collaboratable_type, collaboratable_id)
```

#### `invitations` table
```ruby
{
  id: uuid (PK)
  invitable_type: string (polymorphic: "List" or "ListItem")
  invitable_id: uuid (polymorphic foreign key)
  user_id: uuid (FK to users, OPTIONAL - only set when accepted)
  email: string (OPTIONAL - only set when inviting non-registered users)
  invitation_token: string (unique, secure token)
  invitation_sent_at: timestamp
  invitation_accepted_at: timestamp (NULL until accepted)
  invited_by_id: uuid (FK to users)
  permission: integer (0=read, 1=write)
  created_at: timestamp
  updated_at: timestamp
}

# Indexes
- UNIQUE: (invitable_id, invitable_type, email) WHERE email IS NOT NULL
- UNIQUE: (invitable_id, invitable_type, user_id) WHERE user_id IS NOT NULL
- UNIQUE: (invitation_token)
- Regular: (email)
- Polymorphic: (invitable_type, invitable_id)
```

#### `roles` table (via Rolify - already exists)
Used for role-based access control on Collaborator model

#### `logidze_data` table (via Logidze - already exists)
Tracks audit history of all model changes including collaboration permission changes

### 2.2 Key Design Decisions

1. **Polymorphic Associations**: Both tables use polymorphic associations to support Lists and ListItems
2. **Dual State Tracking**: 
   - `invitations` tracks the invitation lifecycle (pending → accepted)
   - `collaborators` tracks active collaborations
3. **Email-based Invitations**: Users can be invited by email even if they don't have an account
4. **Token Security**: Using Rails 8's `generates_token_for` with 7-day expiration
5. **Unique Constraints**: Prevent duplicate invitations/collaborations per resource
6. **Logidze Audit Trail**: All collaboration changes are audited in `logidze_data` table
7. **Rolify Integration**: Extended permission model for delegation scenarios

---

## 3. Invitation Flow Architecture

### 3.1 High-Level Invitation Flow

```
┌──────────────────────────────────────────────────────────────┐
│                    Invitation Initiation                      │
│                                                               │
│  Owner clicks "Invite" → Enters email → Selects permission   │
│  (optional: grants can_invite_collaborators role)            │
└──────────────────────────────┬────────────────────────────────┘
                               │
                               ▼
                      ┌────────────────────┐
                      │  Check if user     │
                      │  exists?           │
                      └────────────┬───────┘
                                   │
                    ┌──────────────┼─────────────┐
                    │                            │
               [YES]│                            │[NO]
                    ▼                            ▼
        ┌────────────────────────┐   ┌────────────────────────┐
        │ Registered User        │   │ Unregistered User      │
        │ Path                   │   │ Path                   │
        └────────────┬───────────┘   └────────────┬───────────┘
                     │                            │
                     ▼                            ▼
        ┌────────────────────────┐   ┌────────────────────────┐
        │ Create                 │   │ Create Invitation      │
        │ Collaborator           │   │ (email-based)          │
        │ immediately            │   │                        │
        │ (with optional role)   │   │                        │
        └────────────┬───────────┘   └────────────┬───────────┘
                     │                            │
                     ▼                            ▼
        ┌────────────────────────┐   ┌────────────────────────┐
        │ Send email             │   │ Send invitation        │
        │ notification           │   │ email with token       │
        │ "You've been added..."  │   │ (link to signup)       │
        └────────────────────────┘   └────────────┬───────────┘
                                                  │
                                  ┌───────────────┼──────────────┐
                                  │               │              │
                                  ▼               ▼              ▼
                          ┌──────────────┐ ┌──────────────┐
                          │ User creates │ │ User signs   │
                          │ account      │ │ in (already  │
                          │              │ │ registered)  │
                          └──────┬───────┘ └──────┬───────┘
                                 │                │
                                 └────────┬───────┘
                                          │
                                          ▼
                         ┌────────────────────────────┐
                         │ Accept invitation          │
                         │ (verify email match)       │
                         └────────────┬───────────────┘
                                      │
                                      ▼
                         ┌────────────────────────────┐
                         │ Create Collaborator        │
                         │ Update Invitation          │
                         │ (mark accepted)            │
                         │ Grant optional roles       │
                         └────────────────────────────┘
```

### 3.2 Detailed Flow Scenarios

#### Scenario A: Inviting Registered User (with optional delegation role)

1. **Owner Action**: Enters email `alice@example.com` with `write` permission
2. **Optional**: Selects "Alice can invite others" checkbox
3. **System Check**: `User.find_by(email: 'alice@example.com')` → Found
4. **Validation**: Ensure Alice is not already a collaborator
5. **Create Collaborator**: 
   ```ruby
   Collaborator.create!(
     collaboratable: @list,
     user: alice,
     permission: :write
   )
   # Grant optional role if selected
   collaborator.add_role(:can_invite_collaborators) if params[:can_invite]
   ```
6. **Send Notification**: Email to Alice with link to the list
7. **Immediate Access**: Alice can access the list immediately

#### Scenario B: Inviting Unregistered User

1. **Owner Action**: Enters email `bob@example.com` with `read` permission
2. **System Check**: `User.find_by(email: 'bob@example.com')` → Not Found
3. **Create Invitation**:
   ```ruby
   invitation = Invitation.create!(
     invitable: @list,
     email: 'bob@example.com',
     permission: :read,
     invited_by: current_user
   )
   ```
4. **Generate Token**: Rails 8's `generates_token_for :invitation` (7-day expiration)
5. **Send Email**: Invitation email with signup link + token
6. **Bob's Journey**:
   - Clicks link → Lands on signup page
   - Creates account → Email verification
   - Auto-accept invitation if emails match
   - Redirected to the shared list

#### Scenario C: Delegating with Sub-Assignment Rights (ListItem)

1. **Manager**: Assigns task (ListItem) to team lead with `write` permission
2. **Grant Role**: Manager selects "Can delegate to others"
3. **Team Lead**: Receives notification, accepts
4. **Team Lead Action**: Can now assign same task to team members
5. **Team Member**: Gets invited with appropriate permission level
6. **Audit Trail**: Logidze tracks all permission changes

---

## 4. Permission System

### 4.1 Permission Matrix

| Action | Owner | Write Collaborator | Read Collaborator | Public (if enabled) |
|--------|-------|-------------------|-------------------|---------------------|
| View list/items | ✅ | ✅ | ✅ | ✅ (if public) |
| Create items | ✅ | ✅ | ❌ | ✅ (if public_write) |
| Edit items | ✅ | ✅ | ❌ | ✅ (if public_write) |
| Complete items | ✅ | ✅ | ❌ | ✅ (if public_write) |
| Delete items | ✅ | ✅ | ❌ | ❌ |
| Assign items | ✅ | ✅ | ❌ | ❌ |
| Invite collaborators | ✅ | ✅* | ❌ | ❌ |
| Change permissions | ✅ | ❌ | ❌ | ❌ |
| Remove collaborators | ✅ | ❌ | ❌ | ❌ |
| Delete list | ✅ | ❌ | ❌ | ❌ |
| Toggle public access | ✅ | ❌ | ❌ | ❌ |

*Write collaborators can invite only if granted `can_invite_collaborators` role

### 4.2 Permission Checking

Using Pundit policies (established pattern) with Rolify role checks:

```ruby
# app/policies/list_policy.rb
class ListPolicy < ApplicationPolicy
  def update?
    record.owner == user ||
    record.collaborators.permission_write.exists?(user: user)
  end

  def manage_collaborators?
    record.owner == user ||
    (record.collaborators.permission_write.exists?(user: user) &&
     collaborator_for_user&.has_role?(:can_invite_collaborators))
  end

  def destroy?
    record.owner == user # Only owner can delete
  end

  private

  def collaborator_for_user
    record.collaborators.find_by(user: user)
  end
end

# app/policies/list_item_policy.rb
class ListItemPolicy < ApplicationPolicy
  def update?
    # Owner of the list
    return true if record.list.owner == user
    
    # Write permission on the list
    return true if record.list.collaborators.permission_write.exists?(user: user)
    
    # Write permission on the specific item
    return true if record.collaborators.permission_write.exists?(user: user)
    
    # Assigned user can update their own item
    return true if record.assigned_user_id == user.id
    
    false
  end

  def invite_collaborators?
    # Owner of the list
    return true if record.list.owner == user
    
    # Write permission on list with role
    list_collab = record.list.collaborators.find_by(user: user)
    return true if list_collab&.permission_write? && list_collab&.has_role?(:can_invite_collaborators)
    
    # Write permission on item with role
    item_collab = record.collaborators.find_by(user: user)
    return true if item_collab&.permission_write? && item_collab&.has_role?(:can_invite_collaborators)
    
    false
  end
end
```

---

## 5. Service Layer Architecture

### 5.1 InvitationService

**Purpose**: Handle all invitation logic

```ruby
# app/services/invitation_service.rb
class InvitationService
  def initialize(invitable, inviter)
    @invitable = invitable  # List or ListItem
    @inviter = inviter      # Current user sending invitation
  end

  # Main entry point
  def invite(email, permission, grant_roles = {})
    existing_user = User.find_by(email: email)
    
    if existing_user
      add_existing_user(existing_user, permission, grant_roles)
    else
      invite_new_user(email, permission, grant_roles)
    end
  end

  # For existing registered users
  def add_existing_user(user, permission, grant_roles = {})
    # Validation: can't invite owner
    return failure("Cannot invite the owner") if owner?(user)
    
    # Check if already a collaborator
    collaborator = @invitable.collaborators.find_or_initialize_by(user: user)
    
    if collaborator.persisted?
      # Update existing permission
      if collaborator.update(permission: permission)
        grant_optional_roles(collaborator, grant_roles)
        success("#{user.name}'s permission updated")
      else
        failure(collaborator.errors.full_messages)
      end
    else
      # Create new collaborator
      collaborator.permission = permission
      if collaborator.save
        grant_optional_roles(collaborator, grant_roles)
        CollaborationMailer.added_to_resource(collaborator).deliver_later
        success("#{user.name} added as collaborator")
      else
        failure(collaborator.errors.full_messages)
      end
    end
  end

  # For unregistered users
  def invite_new_user(email, permission, grant_roles = {})
    return failure("Cannot invite the owner") if owner_email?(email)
    
    invitation = @invitable.invitations.build(
      email: email,
      permission: permission,
      invited_by: @inviter,
      granted_roles: grant_roles.to_json  # Store roles to grant upon acceptance
    )
    
    if invitation.save
      CollaborationMailer.invitation(invitation).deliver_later
      success("Invitation sent to #{email}")
    else
      failure(invitation.errors.full_messages)
    end
  end

  # Resend invitation
  def resend(invitation)
    invitation.update!(
      invitation_token: invitation.generate_invitation_token,
      invitation_sent_at: Time.current
    )
    
    CollaborationMailer.invitation_reminder(invitation).deliver_later
    success("Invitation resent successfully!")
  end

  private

  def owner?(user)
    case @invitable
    when List
      @invitable.owner == user
    when ListItem
      @invitable.list.owner == user
    else
      false
    end
  end

  def owner_email?(email)
    case @invitable
    when List
      @invitable.owner.email == email
    when ListItem
      @invitable.list.owner.email == email
    else
      false
    end
  end

  def grant_optional_roles(collaborator, roles = {})
    roles.each do |role_name, grant|
      collaborator.add_role(role_name) if grant && role_name.to_s.match?(/^can_/)
    end
  end

  def success(message)
    OpenStruct.new(success?: true, message: message)
  end

  def failure(errors)
    OpenStruct.new(success?: false, errors: Array(errors))
  end
end
```

### 5.2 CollaborationAcceptanceService

**Purpose**: Handle invitation acceptance flow

```ruby
# app/services/collaboration_acceptance_service.rb
class CollaborationAcceptanceService
  def initialize(invitation_token)
    @invitation_token = invitation_token
  end

  def accept(accepting_user)
    invitation = Invitation.find_by_invitation_token(@invitation_token)
    
    return failure("Invalid or expired invitation") unless invitation
    return failure("Invitation already accepted") if invitation.accepted?
    
    # Verify email match
    unless accepting_user.email == invitation.email
      return failure("Email mismatch. This invitation is for #{invitation.email}")
    end
    
    ActiveRecord::Base.transaction do
      # Create collaborator
      collaborator = invitation.invitable.collaborators.create!(
        user: accepting_user,
        permission: invitation.permission
      )
      
      # Grant roles if specified
      if invitation.granted_roles.present?
        roles = JSON.parse(invitation.granted_roles)
        roles.each do |role_name, grant|
          collaborator.add_role(role_name) if grant
        end
      end
      
      # Mark invitation as accepted
      invitation.update!(
        user: accepting_user,
        invitation_accepted_at: Time.current
      )
      
      success(
        collaborator: collaborator,
        resource: invitation.invitable,
        message: "You've joined #{invitation.invitable.title}!"
      )
    end
  rescue ActiveRecord::RecordInvalid => e
    failure(e.record.errors.full_messages)
  end

  private

  def success(data)
    OpenStruct.new(success?: true, **data)
  end

  def failure(errors)
    OpenStruct.new(success?: false, errors: Array(errors))
  end
end
```

---

## 6. Controller Architecture

### 6.1 InvitationsController

**Purpose**: Handle invitation acceptance and viewing

```ruby
# app/controllers/invitations_controller.rb
class InvitationsController < ApplicationController
  skip_before_action :authenticate_user!, only: [:show, :accept]

  # GET /invitations/:token
  # Preview invitation before accepting
  def show
    @invitation = Invitation.find_by_invitation_token(params[:token])
    
    unless @invitation
      redirect_to root_path, alert: "Invalid or expired invitation"
      return
    end

    if @invitation.accepted?
      redirect_to @invitation.invitable, notice: "This invitation has already been accepted"
      return
    end

    @invitable = @invitation.invitable
    @invited_by = @invitation.invited_by

    # If user is logged in and emails match, auto-accept
    if current_user && current_user.email == @invitation.email
      accept_invitation
    end
  end

  # POST /invitations/:token/accept
  def accept
    unless current_user
      # Store token in session and redirect to signup
      session[:pending_invitation_token] = params[:token]
      redirect_to new_registration_path, notice: "Please sign up or log in to accept this invitation"
      return
    end

    accept_invitation
  end

  # DELETE /invitations/:id
  def destroy
    @invitation = Invitation.find(params[:id])
    authorize @invitation

    @invitation.destroy
    
    respond_to do |format|
      format.html { redirect_back fallback_location: root_path, notice: "Invitation cancelled" }
      format.turbo_stream
    end
  end

  private

  def accept_invitation
    service = CollaborationAcceptanceService.new(params[:token])
    result = service.accept(current_user)

    if result.success?
      session.delete(:pending_invitation_token)
      redirect_to result.resource, notice: result.message
    else
      redirect_to root_path, alert: result.errors.join(", ")
    end
  end
end
```

### 6.2 CollaboratorsController

The existing `CollaboratorsController` handles most collaboration management and has been extended to support:
- Polymorphic routing (List and ListItem collaborators)
- Role assignment for delegation scenarios
- Turbo Streams for real-time updates
- Logidze audit tracking via `has_logidze` on Collaborator model

---

## 7. Email/Mailer Architecture

### 7.1 CollaborationMailer

```ruby
# app/mailers/collaboration_mailer.rb
class CollaborationMailer < ApplicationMailer
  default from: "noreply@listopia.com"

  # For new user invitations (email-based)
  def invitation(invitation)
    @invitation = invitation
    @invitable = invitation.invitable
    @invited_by = invitation.invited_by
    @invitation_url = invitation_url(invitation.invitation_token)

    mail(
      to: @invitation.email,
      subject: "#{@invited_by.name} invited you to collaborate on #{@invitable.title}"
    )
  end

  # For registered users added directly
  def added_to_resource(collaborator)
    @collaborator = collaborator
    @collaboratable = collaborator.collaboratable
    @resource_url = polymorphic_url(@collaboratable)

    mail(
      to: @collaborator.user.email,
      subject: "You've been added as a collaborator on #{@collaboratable.title}"
    )
  end

  # Reminder for pending invitations
  def invitation_reminder(invitation)
    @invitation = invitation
    @invitable = invitation.invitable
    @invited_by = invitation.invited_by
    @invitation_url = invitation_url(invitation.invitation_token)

    mail(
      to: @invitation.email,
      subject: "Reminder: Invitation to collaborate on #{@invitable.title}"
    )
  end

  # When collaborator is removed
  def removed_from_resource(user, collaboratable)
    @user = user
    @collaboratable = collaboratable

    mail(
      to: @user.email,
      subject: "You've been removed from #{@collaboratable.title}"
    )
  end

  # When permission changes
  def permission_updated(collaborator, old_permission)
    @collaborator = collaborator
    @collaboratable = collaborator.collaboratable
    @old_permission = old_permission
    @new_permission = collaborator.permission
    @resource_url = polymorphic_url(@collaboratable)

    mail(
      to: @collaborator.user.email,
      subject: "Your permission has been updated for #{@collaboratable.title}"
    )
  end
end
```

---

## 8. AI Integration Architecture

### 8.1 Chat-Based Invitations with Disambiguation

Users can invite collaborators through the AI chat interface. The AI agent can:

1. **Parse natural language requests**:
   - "Invite alice@example.com to my grocery list with write access"
   - "Share my project plan with bob@example.com, read-only"
   - "Add carol@example.com as a collaborator on task #5"

2. **Handle Resource Disambiguation**:
   - If user has multiple lists/items with the same or similar name
   - AI presents a menu for user selection before executing invitation
   - Example: "I found 3 lists named 'Project'. Which one?"

3. **Execute invitation workflow**:
   - Find the correct list/item (with user confirmation if ambiguous)
   - Validate permissions
   - Call `InvitationService`
   - Return confirmation with collaboration details

### 8.2 MCP Tool: invite_collaborator

```ruby
# app/services/mcp_tools/collaboration_tools.rb
module McpTools
  class CollaborationTools
    def initialize(user, context)
      @user = user
      @context = context
    end

    # MCP Tool Definition
    def tools
      [
        {
          name: "invite_collaborator",
          description: "Invite a user to collaborate on a list or list item",
          input_schema: {
            type: "object",
            properties: {
              resource_type: {
                type: "string",
                enum: ["List", "ListItem"],
                description: "Type of resource to share"
              },
              resource_id: {
                type: "string",
                description: "UUID of the list or list item"
              },
              email: {
                type: "string",
                format: "email",
                description: "Email of the person to invite"
              },
              permission: {
                type: "string",
                enum: ["read", "write"],
                description: "Permission level for the collaborator"
              },
              can_invite: {
                type: "boolean",
                description: "Allow this collaborator to invite others (delegation)"
              }
            },
            required: ["resource_type", "resource_id", "email", "permission"]
          }
        },
        {
          name: "list_resources_for_disambiguation",
          description: "Get list of resources matching a search term for disambiguation",
          input_schema: {
            type: "object",
            properties: {
              resource_type: {
                type: "string",
                enum: ["List", "ListItem"],
                description: "Type of resource"
              },
              search_term: {
                type: "string",
                description: "Search term to find matching resources"
              }
            },
            required: ["resource_type", "search_term"]
          }
        }
      ]
    end

    # Tool Implementation - Disambiguation
    def list_resources_for_disambiguation(resource_type:, search_term:)
      resources = case resource_type
      when "List"
        @user.lists.where("title ILIKE ?", "%#{search_term}%").limit(5)
      when "ListItem"
        ListItem.joins(:list)
                .where(lists: { user_id: @user.id })
                .where("list_items.title ILIKE ?", "%#{search_term}%")
                .limit(5)
      else
        return error_response("Invalid resource type")
      end

      if resources.empty?
        {
          success: false,
          message: "No #{resource_type} found matching '#{search_term}'"
        }
      elsif resources.size == 1
        {
          success: true,
          single_match: true,
          resource: format_resource(resources.first)
        }
      else
        {
          success: true,
          multiple_matches: true,
          resources: resources.map { |r| format_resource(r) },
          message: "Found #{resources.size} matching #{resource_type}. Please select one."
        }
      end
    end

    # Tool Implementation - Invitation
    def invite_collaborator(resource_type:, resource_id:, email:, permission:, can_invite: false)
      # Find resource
      resource = case resource_type
      when "List"
        List.find(resource_id)
      when "ListItem"
        ListItem.find(resource_id)
      else
        return error_response("Invalid resource type")
      end

      # Authorization check
      unless can_invite?(resource)
        return error_response("You don't have permission to invite collaborators")
      end

      # Use InvitationService
      service = InvitationService.new(resource, @user)
      grant_roles = { can_invite_collaborators: can_invite }
      result = service.invite(email, permission, grant_roles)

      if result.success?
        {
          success: true,
          message: result.message,
          resource: {
            type: resource_type,
            id: resource_id,
            title: resource.title
          },
          invitee: email,
          permission: permission,
          can_invite_others: can_invite
        }
      else
        error_response(result.errors)
      end
    rescue ActiveRecord::RecordNotFound
      error_response("Resource not found")
    end

    private

    def format_resource(resource)
      {
        id: resource.id,
        title: resource.title,
        type: resource.class.name,
        description: resource.is_a?(ListItem) ? "Item in #{resource.list.title}" : resource.description
      }
    end

    def can_invite?(resource)
      case resource
      when List
        resource.owner == @user ||
        (resource.collaborators.permission_write.exists?(user: @user) &&
         resource.collaborators.find_by(user: @user)&.has_role?(:can_invite_collaborators))
      when ListItem
        resource.list.owner == @user ||
        (resource.list.collaborators.permission_write.exists?(user: @user) &&
         resource.list.collaborators.find_by(user: @user)&.has_role?(:can_invite_collaborators)) ||
        (resource.collaborators.permission_write.exists?(user: @user) &&
         resource.collaborators.find_by(user: @user)&.has_role?(:can_invite_collaborators))
      else
        false
      end
    end

    def error_response(errors)
      {
        success: false,
        error: Array(errors).join(", ")
      }
    end
  end
end
```

### 8.3 Integration with AiAgentMcpService

Add collaboration tools to the MCP service:

```ruby
# app/services/ai_agent_mcp_service.rb
class AiAgentMcpService
  def initialize(user:, context: {})
    @user = user
    @context = context
    @chat = find_or_create_chat
    @extracted_data = {}
    @user_tools = McpTools::UserManagementTools.new(user, context)
    @collaboration_tools = McpTools::CollaborationTools.new(user, context)
  end

  def available_tools
    [
      # ... existing tools ...
      *@collaboration_tools.tools
    ]
  end

  def execute_tool_call(tool_name, arguments)
    case tool_name
    when "invite_collaborator"
      @collaboration_tools.invite_collaborator(**arguments.symbolize_keys)
    when "list_resources_for_disambiguation"
      @collaboration_tools.list_resources_for_disambiguation(**arguments.symbolize_keys)
    # ... existing tool handlers ...
    end
  end
end
```

---

## 9. Frontend Architecture

### 9.1 Turbo Streams for Real-Time Updates

All collaboration UI uses Turbo Streams for reactive updates:

```ruby
# app/views/collaborators/create.turbo_stream.erb
<%= turbo_stream.append "collaborators-list" do %>
  <%= render partial: "collaborators/collaborator", locals: { collaborator: @collaborator } %>
<% end %>

<%= turbo_stream.append "invitations-list" do %>
  <%= render partial: "invitations/invitation", locals: { invitation: @invitation } %>
<% end %>

<%= turbo_stream.replace "flash-messages" do %>
  <%= render partial: "shared/flash", locals: { notice: "Collaborator added successfully!" } %>
<% end %>
```

### 9.2 Collaboration Management UI

Accessible from list show page:

```html
<!-- app/views/lists/show.html.erb -->
<div class="collaboration-section">
  <h3>Collaborators</h3>
  
  <div id="collaborators-list">
    <%= render @list.collaborators %>
  </div>
  
  <h3>Pending Invitations</h3>
  
  <div id="invitations-list">
    <%= render @list.invitations.pending %>
  </div>
  
  <% if policy(@list).manage_collaborators? %>
    <%= render "collaborators/form", collaboratable: @list %>
  <% end %>
</div>
```

### 9.3 Invitation Form with Role Selection

```html
<!-- app/views/collaborators/_form.html.erb -->
<%= form_with url: collaborators_path, data: { turbo: true } do |f| %>
  <%= hidden_field_tag :list_id, collaboratable.id if collaboratable.is_a?(List) %>
  <%= hidden_field_tag :list_item_id, collaboratable.id if collaboratable.is_a?(ListItem) %>
  
  <div class="form-group">
    <%= f.label :email, "Email address" %>
    <%= f.email_field :email, required: true, class: "form-control" %>
  </div>
  
  <div class="form-group">
    <%= f.label :permission %>
    <%= f.select :permission, 
          options_for_select([
            ["Read Only", "read"],
            ["Read & Write", "write"]
          ], "write"),
          {},
          class: "form-control" %>
  </div>
  
  <div class="form-group">
    <%= f.label :can_invite_collaborators, "Allow this person to invite others" %>
    <%= f.check_box :can_invite_collaborators %>
    <small class="text-muted">Only available for write permission</small>
  </div>
  
  <%= f.submit "Invite", class: "btn btn-primary" %>
<% end %>
```

---

## 10. Security Considerations

### 10.1 Token Security

- **Rails 8 Token Generation**: Uses `generates_token_for` with signed/encrypted tokens
- **Expiration**: 7-day expiration on invitation tokens
- **Single Use**: Tokens should be invalidated after acceptance
- **HTTPS Only**: All invitation URLs must use HTTPS in production

### 10.2 Authorization Checks

- **Every Action**: Use Pundit policies for all collaboration actions
- **Email Verification**: Only verified users can accept invitations
- **Owner Protection**: Prevent inviting the owner as a collaborator
- **Duplicate Prevention**: Database constraints prevent duplicate collaborations
- **Role Validation**: Verify roles via Rolify before granting permissions

### 10.3 Rate Limiting

Use Rails 8.1 throttling with monitoring and logging:

```ruby
# config/initializers/rack_attack.rb
Rack::Attack.throttle("invitations/ip", limit: 10, period: 1.hour) do |req|
  if req.path == "/collaborators" && req.post?
    req.ip
  end
end

# Log all throttling attempts
Rack::Attack.throttle("invitations/user", limit: 20, period: 1.hour) do |req|
  if req.path == "/collaborators" && req.post?
    Rails.logger.warn(
      event: "invitation_rate_limit_attempt",
      ip: req.ip,
      timestamp: Time.current
    )
    req.authenticated_user_id if req.authenticated_user_id
  end
end
```

---

## 11. Monitoring & Metrics

### 11.1 Key Metrics to Track

```ruby
# app/models/concerns/collaboration_analytics.rb
module CollaborationAnalytics
  extend ActiveSupport::Concern

  class_methods do
    def invitation_metrics
      {
        total_sent: Invitation.count,
        pending: Invitation.pending.count,
        accepted: Invitation.accepted.count,
        acceptance_rate: acceptance_rate,
        avg_acceptance_time: avg_acceptance_time
      }
    end

    def collaboration_metrics
      {
        total_collaborations: Collaborator.count,
        active_collaborations: active_collaborations_count,
        avg_collaborators_per_list: avg_collaborators_per_list,
        permission_distribution: permission_distribution
      }
    end

    private

    def acceptance_rate
      total = Invitation.count
      return 0 if total.zero?
      
      (Invitation.accepted.count.to_f / total * 100).round(2)
    end

    def avg_acceptance_time
      accepted = Invitation.accepted
                          .where.not(invitation_accepted_at: nil)
      
      return 0 if accepted.empty?
      
      times = accepted.map do |inv|
        (inv.invitation_accepted_at - inv.invitation_sent_at) / 1.hour
      end
      
      (times.sum / times.size).round(2)
    end
  end
end
```

### 11.2 Logging

```ruby
# Log collaboration events
Rails.logger.info({
  event: "collaboration_created",
  list_id: @list.id,
  collaborator_id: @collaborator.id,
  permission: @collaborator.permission,
  inviter_id: current_user.id
}.to_json)

# Log invitation acceptance
Rails.logger.info({
  event: "invitation_accepted",
  invitation_id: invitation.id,
  resource_type: invitation.invitable_type,
  resource_id: invitation.invitable_id,
  acceptance_time_hours: (Time.current - invitation.invitation_sent_at) / 1.hour
}.to_json)
```

---

## 12. Audit Trail & History

### 12.1 Logidze Integration

All collaboration changes are automatically tracked via Logidze:

```ruby
# app/models/collaborator.rb
class Collaborator < ApplicationRecord
  has_logidze  # Automatic audit trail

  # Logidze tracks all changes to:
  # - permission (read → write)
  # - Assigned roles (via Rolify associations)
  # - created_at, updated_at
end
```

### 12.2 Accessing Collaboration History

```ruby
collaborator = Collaborator.find(id)

# Get full history of changes
history = collaborator.log_data.versions  # Returns array of all changes

# Find when permission was changed
collaborator.log_data.versions.each do |version|
  if version['c']['permission'].present?
    puts "Permission changed to: #{version['c']['permission']}"
    puts "Changed at: #{Time.at(version['ts'] / 1000)}"
  end
end
```

### 12.3 Collaboration Activity Feed (Future Enhancement)

Track and display collaboration activity:

```ruby
# Get recent collaboration changes
Collaborator.joins(:log_data)
            .where(collaboratable: @list)
            .order(updated_at: :desc)
            .limit(10)
```

---

## 13. Routes Configuration

### 13.1 Collaboration Routes

The routes are already defined in `config/routes.rb`:

```ruby
# Lists with nested collaborations
resources :lists do
  resources :collaborations, except: [ :show, :new, :edit ] do
    member do
      patch :resend
    end
    collection do
      get :accept, path: "accept/:token", as: :accept
    end
  end
  # ... other list routes ...
end

# ListItems with nested collaborations
resources :list_items do
  resources :collaborations, except: [ :show, :new, :edit ]
end

# Standalone invitation routes
resources :invitations, only: [:show, :destroy], param: :token do
  member do
    post :accept
  end
end
```

### 13.2 Route Helpers

```ruby
# Generate invitation URL
invitation_url(invitation.invitation_token)
# => https://listopia.com/invitations/abc123xyz

# Collaborators for a list
list_collaborations_path(@list)
# => /lists/uuid/collaborations

# Accept invitation
accept_invitation_path(token: token)
# => /invitations/abc123xyz/accept
```

---

## 14. Reusable Patterns from Admin Invitation

The admin user invitation flow provides excellent patterns reused here:

### 14.1 Token Generation Pattern

```ruby
# Admin pattern (User model)
generates_token_for :email_verification, expires_in: 24.hours
generates_token_for :magic_link, expires_in: 15.minutes

# Collaboration pattern (Invitation model)
generates_token_for :invitation, expires_in: 7.days
```

### 14.2 Email Verification Flow

Both flows use session storage for pending operations:

```ruby
# Admin invitation (RegistrationsController)
session[:pending_collaboration_token] = params[:token]

# Collaboration invitation (InvitationsController)
session[:pending_invitation_token] = params[:token]
```

### 14.3 Post-Authentication Flow

```ruby
# SessionsController (existing pattern)
def create
  if @user&.authenticate(params[:password])
    if @user.email_verified?
      sign_in(@user)
      redirect_path = check_pending_collaboration || after_sign_in_path
      redirect_to redirect_path
    end
  end
end

private

def check_pending_collaboration
  return nil unless session[:pending_invitation_token]
  
  invitation = Invitation.find_by_invitation_token(
    session[:pending_invitation_token]
  )
  
  if invitation && invitation.email == current_user.email
    # Auto-accept the invitation
    acceptance_service = CollaborationAcceptanceService.new(
      session[:pending_invitation_token]
    )
    result = acceptance_service.accept(current_user)
    
    session.delete(:pending_invitation_token)
    return result.resource if result.success?
  end
  
  nil
end
```

---

## 15. Edge Cases & Error Handling

### 15.1 Edge Cases to Handle

1. **Invitation to Already-Collaborating User**
   - Update permission instead of creating duplicate
   - Send permission_updated email

2. **User Registers with Different Email**
   - Invitation remains pending
   - Show pending invitations on user dashboard
   - Allow manual linking via email confirmation

3. **Token Expiration**
   - Clear error message
   - Option to request new invitation
   - Notification to original inviter

4. **Invitation Deleted Before Acceptance**
   - Graceful 404 with helpful message
   - Option to request new invitation

5. **List/Item Deleted Before Invitation Accepted**
   - Cascade delete invitations (`dependent: :destroy`)
   - Show friendly error if accessed after deletion

6. **Collaborator Removes Themselves**
   - Allow self-removal (except owner)
   - No email notification (intentional action)

7. **Permission Downgrade (write → read)**
   - Update collaborator record
   - Send notification of change
   - May need to unassign items if write permission required

8. **Multiple Pending Invitations**
   - Accept all matching email invitations on signup
   - Show list of all accepted collaborations
   - Redirect to most recent

### 15.2 Error Messages

```yaml
# config/locales/collaboration.en.yml
en:
  collaboration:
    errors:
      invalid_invitation: "This invitation link is invalid or has expired"
      already_accepted: "This invitation has already been accepted"
      email_mismatch: "This invitation was sent to a different email address"
      not_found: "The shared resource is no longer available"
      permission_denied: "You don't have permission to manage collaborators"
      owner_invitation: "Cannot invite the owner as a collaborator"
      duplicate_invitation: "An invitation for this email already exists"
    success:
      invited: "%{name} has been invited to collaborate"
      added: "%{name} has been added as a collaborator"
      accepted: "You've successfully joined %{title}"
      removed: "Collaborator has been removed"
      permission_updated: "Permission updated successfully"
```

---

## 16. Performance Considerations

### 16.1 Database Queries

**Eager Loading:**
```ruby
# Load collaborators with users
@collaborators = @list.collaborators.includes(:user)

# Load invitations with inviter
@invitations = @list.invitations.pending.includes(:invited_by)

# Load lists with collaborator count
@lists = current_user.lists.includes(:collaborators).with_collaborator_count
```

**N+1 Prevention:**
```ruby
# app/models/list.rb
scope :with_collaborator_count, -> {
  left_joins(:collaborators)
    .select("lists.*, COUNT(DISTINCT collaborators.id) as collaborators_count")
    .group("lists.id")
}
```

### 16.2 Caching Strategy

```ruby
# Cache collaborators list
<% cache [@list, "collaborators", @list.collaborators.maximum(:updated_at)] do %>
  <%= render @list.collaborators %>
<% end %>

# Cache invitation count
Rails.cache.fetch(["list", @list.id, "pending_invitations_count"], expires_in: 5.minutes) do
  @list.invitations.pending.count
end
```

### 16.3 Background Jobs

```ruby
# Send invitation emails asynchronously
CollaborationMailer.invitation(invitation).deliver_later

# Bulk invitation processing
BulkInvitationJob.perform_later(list_id, email_array, permission)

# Cleanup expired invitations
ExpiredInvitationsCleanupJob.perform_later
```

---

## 17. Future Enhancements

### Phase 2 - Short-term (Next 3-6 months)

1. **Collaboration Templates**
   - Pre-defined permission sets
   - Role-based templates (e.g., "Viewer", "Editor", "Admin")

2. **Bulk Operations**
   - Invite multiple users at once
   - Import collaborators from CSV
   - Team/group invitations

3. **Improved Notifications**
   - Real-time browser notifications
   - Digest emails for collaboration activity
   - Notification preferences per list

4. **Collaboration History**
   - Activity feed showing who changed what and when
   - Leverages Logidze for detailed audit trail
   - Displays permission changes with timestamps
   - Shows invitation acceptance and rejection history

### Phase 3 - Long-term (6-12 months)

1. **Team/Organization Support**
   - Create teams
   - Invite entire teams to lists
   - Team-level permission management

2. **Advanced Permissions**
   - Custom permission levels
   - Granular permissions (e.g., can_delete_items, can_reassign)
   - Time-limited access

3. **Collaboration Analytics Dashboard**
   - Visualize collaboration patterns
   - Track team productivity
   - Identify most active collaborators

4. **External Sharing**
   - Share lists publicly with custom permissions
   - Embed lists in external websites
   - API access for integrations

---

## 18. Implementation Checklist

### Phase 2A: Core User Flows
- [ ] Create `InvitationsController` with show, accept, destroy actions
- [ ] Update routes for invitation handling
- [ ] Create `CollaborationAcceptanceService`
- [ ] Update `RegistrationsController#create` to handle pending invitations
- [ ] Update `RegistrationsController#verify_email` to accept invitations
- [ ] Update `SessionsController#create` to check pending invitations
- [ ] Create `InvitationPolicy` for authorization
- [ ] Add `granted_roles` column to invitations table

### Phase 2B: Role-Based Collaboration
- [ ] Add `can_invite_collaborators`, `can_manage_permissions`, `can_remove_collaborators` roles to Rolify
- [ ] Update `InvitationService` to handle role granting
- [ ] Update `CollaborationAcceptanceService` to apply roles on acceptance
- [ ] Update Collaborator policies to check roles via `has_role?`
- [ ] Update UI form to show role checkboxes

### Phase 2C: Email & UI
- [ ] Design and implement invitation email template
- [ ] Design and implement reminder email template
- [ ] Create collaboration management page/section
- [ ] Implement collaborator list component
- [ ] Implement pending invitations list
- [ ] Create invitation form with Turbo
- [ ] Add permission change dropdown
- [ ] Add remove collaborator button with confirmation
- [ ] Add role selector for delegation

### Phase 2D: AI Integration
- [ ] Create `McpTools::CollaborationTools`
- [ ] Implement `invite_collaborator` MCP tool
- [ ] Implement `list_resources_for_disambiguation` MCP tool
- [ ] Add collaboration tools to `AiAgentMcpService`
- [ ] Update AI system prompt with collaboration capabilities
- [ ] Test natural language collaboration requests

### Phase 2E: Polish & Testing
- [ ] Add error handling and user-friendly messages
- [ ] Implement rate limiting on invitations
- [ ] Add disambiguation UI for ambiguous list names
- [ ] Monitor Logidze audit trails
- [ ] Set up collaboration metrics tracking
- [ ] Test all edge cases

### Phase 3: Advanced Features
- [ ] Enable ListItem-level collaboration
- [ ] Update ListItem policies for collaboration
- [ ] Implement assignment vs. collaboration distinction
- [ ] Add bulk invitation functionality
- [ ] Implement invitation reminders (scheduled job)
- [ ] Create collaboration activity feed with Logidze
- [ ] Implement real-time collaboration notifications
- [ ] Add collaboration analytics dashboard

---

## 19. Key Takeaways

### 19.1 Architecture Principles

1. **Reuse Existing Patterns**: The admin invitation flow provides a solid foundation
2. **Polymorphic Design**: Support both Lists and ListItems with minimal code duplication
3. **Two-Phase Flow**: Invitation → Collaboration keeps data clean and auditable
4. **Email-First**: Email is the primary identifier for unregistered users
5. **Security by Default**: Token expiration, email verification, and authorization checks
6. **Role-Based Delegation**: Rolify enables granular control over who can invite others
7. **Audit Everything**: Logidze provides complete history of all collaboration changes

### 19.2 Critical Success Factors

1. **Email Matching**: Always verify email match when accepting invitations
2. **Session Management**: Store pending tokens in session for smooth UX
3. **Real-Time Updates**: Use Turbo Streams for responsive collaboration UI
4. **Clear Permissions**: Make permission levels obvious to users
5. **Graceful Degradation**: Handle edge cases with helpful error messages
6. **Disambiguation**: Present user options when multiple resources match
7. **Audit Trail**: Track all collaboration changes for transparency and compliance

### 19.3 Technical Decisions

1. **Invitation Expiration**: 7 days (longer than admin 24 hours because users may need to register)
2. **Permission Model**: Simple read/write with role-based extensions for delegation
3. **Token Security**: Rails 8's `generates_token_for` with signed tokens
4. **Polymorphic Associations**: Enable code reuse across Lists and ListItems
5. **Service Layer**: Keep controllers thin, use services for business logic
6. **Rolify for Roles**: Extensible role system without database migrations for each new role
7. **Logidze for Audit**: Detached audit trail for complete collaboration history

---

**Document Version**: 1.1  
**Last Updated**: November 12, 2025  
**Author**: Software Architecture Team  
**Status**: Ready for Implementation