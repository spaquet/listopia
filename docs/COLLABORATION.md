# Listopia Collaboration Feature - Detailed Architecture

## Executive Summary

This document outlines a comprehensive architecture for enabling collaboration on Lists and ListItems in Listopia. The design leverages existing patterns (admin user invitation flow) and extends them to support user-to-user collaboration with granular permissions.

---

## 1. Core Concepts & Terminology

### 1.1 Collaboration Types
- **List Collaboration**: Users collaborate on an entire list, seeing all items and being able to edit based on permissions
- **ListItem Collaboration**: Users collaborate on specific items within a list (e.g., task assignment)

### 1.2 User Types
- **Owner**: Creator of the resource (List/ListItem)
- **Collaborator**: User with explicit permissions on a resource
- **Invitee**: User who has been invited but hasn't accepted yet
- **Registered User**: Existing Listopia user
- **Unregistered User**: Email-based invitee who needs to create an account

### 1.3 Permission Levels
Based on existing code, we have a two-tier permission system:
- **`read` (0)**: View-only access
- **`write` (1)**: Full collaboration access (view, edit, comment, complete items)

For future extensibility, we can define semantic meanings:
- **Read**: View list/items, see collaborators
- **Write**: Everything in Read + create/edit/complete/delete items, invite other collaborators

---

## 2. Database Architecture

### 2.1 Existing Tables (Already Implemented)

#### `collaborators` table
```ruby
# Tracks active collaborations
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
# Tracks pending and accepted invitations
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

### 2.2 Key Design Decisions

1. **Polymorphic Associations**: Both tables use polymorphic associations to support Lists and ListItems
2. **Dual State Tracking**: 
   - `invitations` tracks the invitation lifecycle (pending → accepted)
   - `collaborators` tracks active collaborations
3. **Email-based Invitations**: Users can be invited by email even if they don't have an account
4. **Token Security**: Using Rails 8's `generates_token_for` with 7-day expiration
5. **Unique Constraints**: Prevent duplicate invitations/collaborations per resource

---

## 3. Invitation Flow Architecture

### 3.1 High-Level Invitation Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                    Invitation Initiation                        │
│                                                                 │
│  Owner clicks "Invite" → Enters email → Selects permission     │
└─────────────────────┬───────────────────────────────────────────┘
                      │
                      ▼
             ┌────────────────┐
             │  Check if user │
             │  exists?       │
             └────────┬───────┘
                      │
         ┌────────────┴────────────┐
         │                         │
    [YES]│                         │[NO]
         ▼                         ▼
┌─────────────────┐       ┌──────────────────┐
│ Registered User │       │ Unregistered     │
│ Path            │       │ User Path        │
└────────┬────────┘       └────────┬─────────┘
         │                         │
         ▼                         ▼
┌─────────────────┐       ┌──────────────────┐
│ Create          │       │ Create           │
│ Collaborator    │       │ Invitation       │
│ immediately     │       │ (email-based)    │
└────────┬────────┘       └────────┬─────────┘
         │                         │
         ▼                         ▼
┌─────────────────┐       ┌──────────────────┐
│ Send email      │       │ Send invitation  │
│ notification    │       │ email with token │
│ "You've been    │       │ (link to signup) │
│ added..."       │       │                  │
└─────────────────┘       └────────┬─────────┘
                                   │
                          ┌────────┴──────────┐
                          │                   │
                          ▼                   ▼
                  ┌──────────────┐    ┌─────────────┐
                  │ User creates │    │ User signs  │
                  │ account      │    │ in (already │
                  │              │    │ registered) │
                  └──────┬───────┘    └──────┬──────┘
                         │                   │
                         └────────┬──────────┘
                                  │
                                  ▼
                         ┌────────────────┐
                         │ Accept         │
                         │ invitation     │
                         │ (verify email  │
                         │ match)         │
                         └────────┬───────┘
                                  │
                                  ▼
                         ┌────────────────┐
                         │ Create         │
                         │ Collaborator   │
                         │ Update         │
                         │ Invitation     │
                         │ (mark accepted)│
                         └────────────────┘
```

### 3.2 Detailed Flow Scenarios

#### Scenario A: Inviting Registered User

1. **Owner Action**: Enters email `alice@example.com` with `write` permission
2. **System Check**: `User.find_by(email: 'alice@example.com')` → Found
3. **Validation**: Ensure Alice is not already a collaborator
4. **Create Collaborator**: 
   ```ruby
   Collaborator.create!(
     collaboratable: @list,
     user: alice,
     permission: :write
   )
   ```
5. **Send Notification**: Email to Alice with link to the list
6. **Immediate Access**: Alice can access the list immediately

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

#### Scenario C: Inviting User Who Later Registers

1. **Invitation Created**: For `carol@example.com`
2. **Carol Registers**: Creates account separately (not through invitation link)
3. **Email Verification**: Carol verifies `carol@example.com`
4. **Next Login**: System detects pending invitation for `carol@example.com`
5. **Auto-Link**: Create Collaborator, mark Invitation as accepted
6. **Redirect**: Take Carol to the shared list

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
| Invite collaborators | ✅ | ✅ | ❌ | ❌ |
| Change permissions | ✅ | ❌ | ❌ | ❌ |
| Remove collaborators | ✅ | ❌ | ❌ | ❌ |
| Delete list | ✅ | ❌ | ❌ | ❌ |
| Toggle public access | ✅ | ❌ | ❌ | ❌ |

### 4.2 Permission Checking

Using Pundit policies (already established pattern):

```ruby
# app/policies/list_policy.rb
class ListPolicy < ApplicationPolicy
  def update?
    record.owner == user ||
    record.collaborators.permission_write.exists?(user: user)
  end

  def manage_collaborators?
    record.owner == user ||
    record.collaborators.permission_write.exists?(user: user)
  end

  def destroy?
    record.owner == user # Only owner can delete
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
end
```

---

## 5. Service Layer Architecture

### 5.1 InvitationService (Already Exists)

**Purpose**: Handle all invitation logic

```ruby
# app/services/invitation_service.rb
class InvitationService
  def initialize(invitable, inviter)
    @invitable = invitable  # List or ListItem
    @inviter = inviter      # Current user sending invitation
  end

  # Main entry point
  def invite(email, permission)
    existing_user = User.find_by(email: email)
    
    if existing_user
      add_existing_user(existing_user, permission)
    else
      invite_new_user(email, permission)
    end
  end

  # For existing registered users
  def add_existing_user(user, permission)
    # Validation: can't invite owner
    return failure("Cannot invite the owner") if owner?(user)
    
    # Check if already a collaborator
    collaborator = @invitable.collaborators.find_or_initialize_by(user: user)
    
    if collaborator.persisted?
      # Update existing permission
      if collaborator.update(permission: permission)
        success("#{user.name}'s permission updated")
      else
        failure(collaborator.errors.full_messages)
      end
    else
      # Create new collaborator
      collaborator.permission = permission
      if collaborator.save
        CollaborationMailer.added_to_resource(collaborator).deliver_later
        success("#{user.name} added as collaborator")
      else
        failure(collaborator.errors.full_messages)
      end
    end
  end

  # For unregistered users
  def invite_new_user(email, permission)
    return failure("Cannot invite the owner") if owner_email?(email)
    
    invitation = @invitable.invitations.build(
      email: email,
      permission: permission,
      invited_by: @inviter
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

  def success(message)
    OpenStruct.new(success?: true, message: message)
  end

  def failure(errors)
    OpenStruct.new(success?: false, errors: Array(errors))
  end
end
```

### 5.2 CollaborationAcceptanceService (New)

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

### 6.1 InvitationsController (New)

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

### 6.2 CollaboratorsController Updates

The existing `CollaboratorsController` already handles most collaboration management. Key points:

- **Polymorphic routing**: Uses `list_id` or `list_item_id` params
- **Authorization**: Uses Pundit for permission checks
- **Real-time updates**: Uses Turbo Streams for UI updates

---

## 7. Email/Mailer Architecture

### 7.1 CollaborationMailer (Already Exists)

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

### 8.1 Chat-Based Invitations

Users can invite collaborators through the AI chat interface. The AI agent can:

1. **Parse natural language requests**:
   - "Invite alice@example.com to my grocery list with write access"
   - "Share my project plan with bob@example.com, read-only"
   - "Add carol@example.com as a collaborator on task #5"

2. **Execute invitation workflow**:
   - Find the correct list/item
   - Validate permissions
   - Call `InvitationService`
   - Return confirmation

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
              }
            },
            required: ["resource_type", "resource_id", "email", "permission"]
          }
        }
      ]
    end

    # Tool Implementation
    def invite_collaborator(resource_type:, resource_id:, email:, permission:)
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
      result = service.invite(email, permission)

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
          permission: permission
        }
      else
        error_response(result.errors)
      end
    rescue ActiveRecord::RecordNotFound
      error_response("Resource not found")
    end

    private

    def can_invite?(resource)
      case resource
      when List
        resource.owner == @user ||
        resource.collaborators.permission_write.exists?(user: @user)
      when ListItem
        resource.list.owner == @user ||
        resource.list.collaborators.permission_write.exists?(user: @user) ||
        resource.collaborators.permission_write.exists?(user: @user)
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
    @collaboration_tools = McpTools::CollaborationTools.new(user, context) # NEW
  end

  def available_tools
    [
      # ... existing tools ...
      *@collaboration_tools.tools # Add collaboration tools
    ]
  end

  def execute_tool_call(tool_name, arguments)
    case tool_name
    when "invite_collaborator"
      @collaboration_tools.invite_collaborator(**arguments.symbolize_keys)
    # ... existing tool handlers ...
    end
  end
end
```

---

## 9. Frontend Architecture

### 9.1 Turbo Streams for Real-Time Updates

All collaboration UI should use Turbo Streams for reactive updates:

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

**Location**: Accessible from list show page

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

### 9.3 Invitation Form

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

### 10.3 Rate Limiting

Implement rate limiting on invitation sending to prevent abuse:

```ruby
# config/initializers/rack_attack.rb
Rack::Attack.throttle("invitations/ip", limit: 10, period: 1.hour) do |req|
  if req.path == "/collaborators" && req.post?
    req.ip
  end
end
```

---

## 11. Testing Strategy

### 11.1 Model Tests (RSpec)

```ruby
# spec/models/invitation_spec.rb
RSpec.describe Invitation, type: :model do
  describe "validations" do
    it "requires either email or user_id" do
      invitation = build(:invitation, email: nil, user: nil)
      expect(invitation).not_to be_valid
      expect(invitation.errors[:base]).to include("Either user or email must be present")
    end
    
    it "prevents inviting the owner" do
      list = create(:list)
      invitation = build(:invitation, invitable: list, email: list.owner.email)
      expect(invitation).not_to be_valid
    end
    
    it "prevents duplicate email invitations" do
      invitation = create(:invitation, email: "test@example.com")
      duplicate = build(:invitation, 
        invitable: invitation.invitable, 
        email: "test@example.com"
      )
      expect(duplicate).not_to be_valid
    end
  end
  
  describe "#accept!" do
    it "creates a collaborator and marks invitation as accepted" do
      invitation = create(:invitation, email: "user@example.com")
      user = create(:user, email: "user@example.com")
      
      result = invitation.accept!(user)
      
      expect(result).to be_a(Collaborator)
      expect(invitation.reload.accepted?).to be true
      expect(invitation.user).to eq(user)
    end
  end
end
```

### 11.2 Service Tests

```ruby
# spec/services/invitation_service_spec.rb
RSpec.describe InvitationService do
  let(:list) { create(:list) }
  let(:owner) { list.owner }
  let(:service) { described_class.new(list, owner) }

  describe "#invite existing user" do
    let(:user) { create(:user) }
    
    it "creates a collaborator for registered users" do
      result = service.invite(user.email, :write)
      
      expect(result.success?).to be true
      expect(list.collaborators.find_by(user: user)).to be_present
    end
  end

  describe "#invite new user" do
    it "creates an invitation for unregistered users" do
      result = service.invite("newuser@example.com", :read)
      
      expect(result.success?).to be true
      expect(list.invitations.find_by(email: "newuser@example.com")).to be_present
    end
  end

  describe "#invite owner" do
    it "prevents inviting the owner" do
      result = service.invite(owner.email, :write)
      
      expect(result.success?).to be false
      expect(result.errors).to include(/Cannot invite the owner/)
    end
  end
end
```

### 11.3 Integration Tests (Capybara)

```ruby
# spec/system/collaboration_spec.rb
RSpec.describe "Collaboration", type: :system do
  let(:owner) { create(:user) }
  let(:list) { create(:list, owner: owner) }

  before { sign_in owner }

  describe "inviting registered user" do
    let(:collaborator) { create(:user, email: "collab@example.com") }

    it "adds user as collaborator immediately" do
      visit list_path(list)
      click_on "Manage Collaborators"
      
      fill_in "Email", with: collaborator.email
      select "Read & Write", from: "Permission"
      click_on "Invite"
      
      expect(page).to have_content("#{collaborator.name} added as collaborator")
      expect(list.collaborators.find_by(user: collaborator)).to be_present
    end
  end

  describe "inviting unregistered user" do
    it "sends invitation email" do
      visit list_path(list)
      click_on "Manage Collaborators"
      
      fill_in "Email", with: "newuser@example.com"
      select "Read Only", from: "Permission"
      
      expect {
        click_on "Invite"
      }.to change { ActionMailer::Base.deliveries.count }.by(1)
      
      expect(page).to have_content("Invitation sent to newuser@example.com")
    end
  end

  describe "accepting invitation" do
    let(:invitation) { create(:invitation, invitable: list, email: "invitee@example.com") }
    let(:invitee) { create(:user, email: "invitee@example.com") }

    it "creates collaborator and redirects to list" do
      sign_in invitee
      visit invitation_path(invitation.invitation_token)
      
      expect(page).to have_content("You've joined #{list.title}")
      expect(list.collaborators.find_by(user: invitee)).to be_present
    end
  end
end
```

---

## 12. Migration Plan

### 12.1 Phase 1: Core Infrastructure (Already Complete ✅)

- ✅ `collaborators` table
- ✅ `invitations` table  
- ✅ `Collaborator` model
- ✅ `Invitation` model
- ✅ Polymorphic associations on List and ListItem
- ✅ `InvitationService`
- ✅ `CollaborationMailer`
- ✅ `CollaboratorsController`

### 12.2 Phase 2: User Flows (Implementation Needed)

**2.1 Invitation Acceptance Flow**
- [ ] Create `InvitationsController`
- [ ] Add routes for invitation acceptance
- [ ] Create `CollaborationAcceptanceService`
- [ ] Update `RegistrationsController` to handle pending invitations
- [ ] Update `SessionsController` to check for pending invitations on login

**2.2 Email Templates**
- [ ] Design email template for `invitation.html.erb`
- [ ] Update `added_to_resource.html.erb` template
- [ ] Create `invitation_reminder.html.erb` template

**2.3 UI Components**
- [ ] Collaboration management page/modal
- [ ] Collaborator list display
- [ ] Pending invitations display
- [ ] Invitation form component
- [ ] Permission change dropdown
- [ ] Remove collaborator confirmation

### 12.3 Phase 3: AI Integration

**3.1 MCP Tools**
- [ ] Create `McpTools::CollaborationTools`
- [ ] Implement `invite_collaborator` tool
- [ ] Implement `list_collaborators` tool
- [ ] Implement `remove_collaborator` tool
- [ ] Integrate with `AiAgentMcpService`

**3.2 Natural Language Processing**
- [ ] Train/prompt AI to recognize collaboration requests
- [ ] Extract email, resource, and permission from user messages
- [ ] Provide clear feedback on invitation actions

### 12.4 Phase 4: Advanced Features

**4.1 Collaboration on ListItems**
- [ ] Enable item-level collaboration
- [ ] Update policies for item-level permissions
- [ ] UI for inviting to specific items
- [ ] Assignment vs. collaboration distinction

**4.2 Permission Extensions**
- [ ] Consider adding "comment" permission level
- [ ] Consider adding "admin" permission level (can manage other collaborators)
- [ ] Permission inheritance (list → items)

**4.3 Notifications**
- [ ] Real-time notifications when added to a list
- [ ] Notifications when items are updated
- [ ] Notification preferences

**4.4 Analytics**
- [ ] Track collaboration metrics
- [ ] Show activity by collaborator
- [ ] Collaboration engagement analytics

---

## 13. Routes Configuration

### 13.1 Invitation Routes

```ruby
# config/routes.rb
Rails.application.routes.draw do
  # Invitation acceptance (public routes)
  resources :invitations, only: [:show, :destroy], param: :token do
    member do
      post :accept
      post :resend
    end
  end

  # Collaborator management (nested under resources)
  resources :lists do
    resources :collaborators, only: [:index, :create, :update, :destroy]
    get :share, on: :member # Sharing management page
  end

  resources :list_items do
    resources :collaborators, only: [:index, :create, :update, :destroy]
  end

  # Alternative: Polymorphic route for collaborators
  resources :collaborators, only: [:create, :update, :destroy]
end
```

### 13.2 Route Helpers

```ruby
# Generate invitation URL
invitation_url(invitation.invitation_token)
# => https://listopia.com/invitations/abc123xyz

# Collaborators for a list
list_collaborators_path(@list)
# => /lists/uuid/collaborators

# Accept invitation
accept_invitation_path(token: token)
# => /invitations/abc123xyz/accept
```

---

## 14. Reusable Patterns from Admin Invitation

The admin user invitation flow provides excellent patterns to reuse:

### 14.1 Token Generation Pattern

```ruby
# Admin pattern (User model)
generates_token_for :email_verification, expires_in: 24.hours
generates_token_for :magic_link, expires_in: 15.minutes

# Collaboration pattern (Invitation model)
generates_token_for :invitation, expires_in: 7.days
```

**Similarities:**
- Both use Rails 8's `generates_token_for`
- Both have expiration times
- Both are single-use tokens
- Both use `find_by_[purpose]_token` class methods

### 14.2 Email Verification Flow

**Admin Pattern:**
```
Admin creates user → User.send_admin_invitation! → 
AdminMailer.user_invitation → User clicks link → 
RegistrationsController#setup_password → User sets password → 
User.verify_email! → Sign in user → Redirect to dashboard
```

**Collaboration Pattern:**
```
Owner invites user → Invitation.create! → 
CollaborationMailer.invitation → User clicks link → 
InvitationsController#show → User signs up/logs in → 
CollaborationAcceptanceService.accept → 
Create Collaborator → Redirect to shared resource
```

### 14.3 Session Token Storage

Both flows use session storage for pending operations:

```ruby
# Admin invitation (RegistrationsController)
session[:pending_collaboration_token] = params[:token]

# Collaboration invitation (InvitationsController)
session[:pending_invitation_token] = params[:token]
```

### 14.4 Post-Authentication Flow

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
  return nil unless session[:pending_collaboration_token]
  
  collaboration = ListCollaboration.find_by_invitation_token(
    session[:pending_collaboration_token]
  )
  
  if collaboration && collaboration.email == current_user.email
    collaboration.update!(user: current_user, email: nil)
    session.delete(:pending_collaboration_token)
    return collaboration.list
  end
  
  nil
end
```

**This exact pattern can be reused for collaboration invitations!**

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

```ruby
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

## 17. Monitoring & Metrics

### 17.1 Key Metrics to Track

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

### 17.2 Logging

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

## 18. Future Enhancements

### 18.1 Short-term (Next 3-6 months)

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
   - Audit log of all collaboration changes
   - Track who added/removed whom
   - Permission change history

### 18.2 Long-term (6-12 months)

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

## 19. Implementation Checklist

### Phase 2A: Core User Flows
- [ ] Create `InvitationsController` with show, accept, destroy actions
- [ ] Update routes for invitation handling
- [ ] Create `CollaborationAcceptanceService`
- [ ] Update `RegistrationsController#create` to handle pending invitations
- [ ] Update `RegistrationsController#verify_email` to accept invitations
- [ ] Update `SessionsController#create` to check pending invitations
- [ ] Create `InvitationPolicy` for authorization

### Phase 2B: Email & UI
- [ ] Design and implement invitation email template
- [ ] Design and implement reminder email template
- [ ] Create collaboration management page/section
- [ ] Implement collaborator list component
- [ ] Implement pending invitations list
- [ ] Create invitation form with Turbo
- [ ] Add permission change dropdown
- [ ] Add remove collaborator button with confirmation

### Phase 2C: Polish & Testing
- [ ] Write model tests for Invitation
- [ ] Write model tests for Collaborator
- [ ] Write service tests for InvitationService
- [ ] Write service tests for CollaborationAcceptanceService
- [ ] Write controller tests for InvitationsController
- [ ] Write system tests for invitation flow
- [ ] Write system tests for collaboration management
- [ ] Add error handling and user-friendly messages
- [ ] Implement rate limiting on invitations

### Phase 3: AI Integration
- [ ] Create `McpTools::CollaborationTools`
- [ ] Implement `invite_collaborator` MCP tool
- [ ] Implement `list_collaborators` MCP tool
- [ ] Implement `remove_collaborator` MCP tool
- [ ] Add collaboration tools to `AiAgentMcpService`
- [ ] Update AI system prompt with collaboration capabilities
- [ ] Test natural language collaboration requests
- [ ] Add collaboration examples to AI training

### Phase 4: Advanced Features
- [ ] Enable ListItem-level collaboration
- [ ] Update ListItem policies for collaboration
- [ ] Implement assignment vs. collaboration distinction
- [ ] Add bulk invitation functionality
- [ ] Implement invitation reminders (scheduled job)
- [ ] Add collaboration analytics
- [ ] Create collaboration activity feed
- [ ] Implement real-time collaboration notifications

---

## 20. Key Takeaways

### 20.1 Architecture Principles

1. **Reuse Existing Patterns**: The admin invitation flow provides a solid foundation
2. **Polymorphic Design**: Support both Lists and ListItems with minimal code duplication
3. **Two-Phase Flow**: Invitation → Collaboration keeps data clean and auditable
4. **Email-First**: Email is the primary identifier for unregistered users
5. **Security by Default**: Token expiration, email verification, and authorization checks

### 20.2 Critical Success Factors

1. **Email Matching**: Always verify email match when accepting invitations
2. **Session Management**: Store pending tokens in session for smooth UX
3. **Real-Time Updates**: Use Turbo Streams for responsive collaboration UI
4. **Clear Permissions**: Make permission levels obvious to users
5. **Graceful Degradation**: Handle edge cases with helpful error messages

### 20.3 Technical Decisions

1. **Invitation Expiration**: 7 days (longer than admin 24 hours because users may need to register)
2. **Permission Model**: Simple read/write for initial implementation
3. **Token Security**: Rails 8's `generates_token_for` with signed tokens
4. **Polymorphic Associations**: Enable code reuse across Lists and ListItems
5. **Service Layer**: Keep controllers thin, use services for business logic

---

## Appendix A: Database Schema Reference

```sql
-- Collaborators Table
CREATE TABLE collaborators (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  collaboratable_type VARCHAR NOT NULL,
  collaboratable_id UUID NOT NULL,
  user_id UUID NOT NULL REFERENCES users(id),
  permission INTEGER DEFAULT 0 NOT NULL,
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL,
  
  CONSTRAINT unique_collaboratable_user 
    UNIQUE (collaboratable_id, collaboratable_type, user_id)
);

CREATE INDEX idx_collaborators_on_user ON collaborators(user_id);
CREATE INDEX idx_collaborators_on_collaboratable 
  ON collaborators(collaboratable_type, collaboratable_id);

-- Invitations Table
CREATE TABLE invitations (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  invitable_type VARCHAR NOT NULL,
  invitable_id UUID NOT NULL,
  user_id UUID REFERENCES users(id),
  email VARCHAR,
  invitation_token VARCHAR UNIQUE,
  invitation_sent_at TIMESTAMP,
  invitation_accepted_at TIMESTAMP,
  invited_by_id UUID REFERENCES users(id),
  permission INTEGER DEFAULT 0 NOT NULL,
  created_at TIMESTAMP NOT NULL,
  updated_at TIMESTAMP NOT NULL,
  
  CONSTRAINT unique_invitable_email 
    UNIQUE (invitable_id, invitable_type, email) 
    WHERE email IS NOT NULL,
  
  CONSTRAINT unique_invitable_user 
    UNIQUE (invitable_id, invitable_type, user_id) 
    WHERE user_id IS NOT NULL
);

CREATE INDEX idx_invitations_on_email ON invitations(email);
CREATE INDEX idx_invitations_on_token ON invitations(invitation_token);
CREATE INDEX idx_invitations_on_invitable 
  ON invitations(invitable_type, invitable_id);
```

---

## Appendix B: API Endpoints

```
# Invitation Management
GET    /invitations/:token              # View invitation details
POST   /invitations/:token/accept       # Accept invitation
POST   /invitations/:id/resend          # Resend invitation
DELETE /invitations/:id                 # Cancel invitation

# Collaborator Management
GET    /lists/:list_id/collaborators              # List collaborators
POST   /lists/:list_id/collaborators              # Add collaborator
PATCH  /lists/:list_id/collaborators/:id          # Update permission
DELETE /lists/:list_id/collaborators/:id          # Remove collaborator

GET    /list_items/:item_id/collaborators         # List item collaborators
POST   /list_items/:item_id/collaborators         # Add item collaborator
PATCH  /list_items/:item_id/collaborators/:id     # Update item permission
DELETE /list_items/:item_id/collaborators/:id     # Remove item collaborator

# Sharing Management
GET    /lists/:id/share                  # Sharing management page
```

---

## Appendix C: Environment Variables

```bash
# Collaboration Feature Configuration
LISTOPIA_INVITATION_EXPIRY_DAYS=7
LISTOPIA_MAX_COLLABORATORS_PER_LIST=50
LISTOPIA_MAX_INVITATIONS_PER_HOUR=10
LISTOPIA_ENABLE_COLLABORATION_ANALYTICS=true
LISTOPIA_COLLABORATION_EMAIL_FROM=noreply@listopia.com
```

---

**Document Version**: 1.0  
**Last Updated**: 2025-01-XX  
**Author**: Software Architecture Team  
**Status**: Ready for Implementation