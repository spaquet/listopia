# Phase 2 Implementation Summary: Authorization & Policies

## Status: ✅ COMPLETE

### What Was Implemented

#### 1. New Policies (2)

**OrganizationPolicy** (`app/policies/organization_policy.rb`)
- Actions:
  - `index?` - All authenticated users can see their organizations
  - `show?` - User must be a member of the organization
  - `create?` - All authenticated users can create organizations
  - `update?` - Organization admin or owner
  - `destroy?` - Organization owner only
  - `manage_members?` - Admin or owner
  - `invite_member?` - Admin or owner
  - `remove_member?` - Admin or owner
  - `update_member_role?` - Owner (for any role change), Admin (for member only)
  - `manage_teams?` - Admin or owner
  - `view_audit_logs?` - Admin or owner
  - `suspend?` - Owner only
  - `reactivate?` - Owner only
- Scope: Returns only organizations user is a member of via `organization_memberships`
- Helper method: `user_can_manage?(organization)` - checks org membership and role

**TeamPolicy** (`app/policies/team_policy.rb`)
- Actions:
  - `index?` - User must be in organization
  - `show?` - User must be team member
  - `create?` - User must be org admin or owner
  - `update?` - Team admin or lead
  - `destroy?` - Team admin or lead
  - `manage_members?` - Team admin or lead
  - `add_member?` - Team admin or lead
  - `remove_member?` - Team admin or lead
  - `update_member_role?` - Team admin or lead
- Scope: Teams in organizations user is a member of (via `organization_memberships`)
- Helper methods:
  - `user_is_member?(team)` - checks if user is team member
  - `user_can_manage_teams?(org)` - checks if user can manage teams in org
  - `user_can_manage_team?(team)` - checks if user can manage specific team

#### 2. Updated Policies (1)

**ListPolicy** (`app/policies/list_policy.rb`) - Added organization boundary checks
- `show?` - Check org boundary first: `return false if record.organization_id.present? && !user.in_organization?(record.organization)`
- `update?` - Same org boundary check
- `destroy?` - Same org boundary check
- This prevents cross-org access even if user somehow has collaborator record

#### 3. ApplicationController Enhancements

**Organization Context Methods:**
- `current_organization` - Helper method returning user's current org context
  - Checks session first: `session[:current_organization_id]`
  - Fallback to user's `current_organization_id`
  - Fallback to user's first organization
  - Caches result in `@current_organization`

- `current_organization=(organization)` - Set current organization
  - Updates session: `session[:current_organization_id]`
  - Updates instance variable

- `require_organization!` - Enforce organization requirement
  - Redirects non-authenticated users with message
  - Responds with JSON error for API requests

- `organization_required?` - Hook for controllers to override and require org
  - Returns false by default
  - Can be overridden in subclasses

- `set_current_organization` - Before action to set org context
  - Sets `Current.organization` for model/service use
  - Called automatically as `before_action`

**Helper Methods:**
- Added to `helper_method` list:
  - `current_organization`
  - `current_organization=`
- Makes methods available in views for displaying org context

#### 4. Test Suites (2 new + updates to existing)

**OrganizationPolicy Spec** (~40 examples)
- All action permissions (show, create, update, destroy, manage, invite, etc.)
- Role-based access (owner vs admin vs member)
- Org boundary enforcement (member vs non-member)
- Scope test: user only sees their organizations
- Covers all edge cases and permission transitions

**TeamPolicy Spec** (~45 examples)
- All action permissions (show, create, update, destroy, manage, etc.)
- Role-based access (admin vs lead vs member)
- Org membership requirement
- Team membership requirement
- Scope test: user only sees teams in their organizations
- Covers cross-org access denial

#### 5. Authorization Architecture

**Three-Layer Authorization Pattern:**
1. **Authentication**: User must be signed in
2. **Organization Membership**: User must be member of org (for org-scoped actions)
3. **Role-Based**: User must have appropriate role
4. **Query Scoping**: PolicyScope restricts visible records

**Example Flow:**
```
User requests: GET /organizations/123
1. authenticate_user! - is user logged in?
2. current_organization context set - populate org context
3. authorize @organization, :show? - does policy allow?
   - Check: user.in_organization?(@organization)
4. Response: only if all pass
```

**Policy Scope Usage:**
```ruby
# Index action
@organizations = policy_scope(Organization)
# Returns: only orgs user is member of

# Show action
authorize @organization, :show?
# Checks: user.in_organization?(@organization)
```

### Key Design Decisions

1. **Session-Based Org Context**:
   - Allows users to switch organizations without signing out
   - Session takes precedence over user's stored preference
   - Fallback chain ensures user always has context

2. **Scope Before Action Check**:
   - Scope ensures visibility (prevents seeing org)
   - Action check ensures permission (prevents modifying)
   - Two-layer protection for security

3. **Role Hierarchy**:
   - Organization: member < admin < owner
   - Team: member < lead < admin
   - Owner can always manage, admin has most powers

4. **Org Boundary in ListPolicy**:
   - List can be org-scoped (new) or not (legacy)
   - If org_id present, must check org membership
   - Prevents cross-org access even with collaborator

5. **Flexible Org Requirement**:
   - `require_organization!` for strict enforcement
   - `organization_required?` for controller override
   - Default false to support non-org workflows

### Database Structure for Policies

**organization_memberships table** (used for policy scoping):
```
organization_id (FK) → organizations.id
user_id (FK) → users.id
role (int) → member/admin/owner
status (int) → pending/active/suspended/revoked
Unique constraint: [organization_id, user_id]
```

**team_memberships table** (used for team policies):
```
team_id (FK) → teams.id
user_id (FK) → users.id
organization_membership_id (FK) → organization_memberships.id
role (int) → member/lead/admin
Unique constraint: [team_id, user_id]
```

### Testing Coverage

**Authorization Tests:**
- ✅ All policy methods covered (show, create, update, destroy, manage, etc.)
- ✅ All role combinations tested (owner, admin, member, lead)
- ✅ Cross-org access denial tested
- ✅ Scope tests verify only authorized orgs/teams shown
- ✅ Edge cases (suspended, revoked, pending statuses)

**Example Test Patterns:**
```ruby
# Role-based permission test
context 'when user is admin' do
  before { create(:organization_membership, role: :admin) }
  it { is_expected.to permit(:update) }
end

# Cross-org access denial
context 'when user is not a member' do
  it { is_expected.not_to permit(:show) }
end

# Scope test
it 'includes organizations the user is a member of' do
  expect(Pundit.policy_scope(user, Organization)).to include(user_org)
end
```

### Integration with Existing Code

**Pundit Integration:**
- Uses standard Pundit pattern: `authorize @resource, :action?`
- Scopes with: `policy_scope(Model)`
- Rescue from: `Pundit::NotAuthorizedError`

**Current Helper Pattern:**
- Follows existing `current_user` pattern
- Uses session for persistence (like existing code)
- Integrates with `Current` context object

**Controller Before Actions:**
- `set_current_user` - existing
- `set_current_organization` - new, called after user
- `store_location` - existing

### What's Next (Phase 3)

- [ ] Admin interface: Organizations index, show, members
- [ ] Organization members management page
- [ ] Organization invitations page
- [ ] Audit logs viewer
- [ ] Suspend/reactivate organization functionality
- [ ] Admin user filtering by organization

### Usage Examples for Developers

**In Controllers:**
```ruby
class OrganizationsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_organization, only: [:show, :update, :destroy]
  before_action :require_organization!, only: [:show]

  def show
    authorize @organization, :show?
    @members = @organization.organization_memberships.active
  end

  def update
    authorize @organization, :update?
    @organization.update!(organization_params)
  end

  private

  def set_organization
    @organization = Organization.find(params[:id])
  end
end
```

**In Views:**
```erb
<% if policy(organization).manage_members? %>
  <%= link_to "Manage Members", org_members_path(organization) %>
<% end %>

<h1><%= current_organization.name %> Members</h1>
```

**In Services:**
```ruby
class InvitationService
  def invite_to_organization(email, organization)
    return false unless organization.user_is_admin?(current_user)
    # Create invitation...
  end
end
```

### Security Checklist

- ✅ Organization boundary enforced at policy level
- ✅ Team-org relationship enforced (users must be org members first)
- ✅ Cross-org access denied in policy scope
- ✅ Role-based permissions implemented
- ✅ Session-based org switching allowed but scoped
- ✅ Fallback org selection for logged-in users
- ✅ ListPolicy updated for org boundaries
- ✅ No direct object access without policy check

### Performance Notes

**Query Optimization:**
- Policy scopes use joins to organization_memberships
- Eager load through associations where possible
- Index on [organization_id, user_id] for membership lookups
- Session stores org_id to avoid repeated lookups

**Caching:**
- `current_organization` cached in instance variable
- Avoid N+1 by using `includes(:organization_memberships)`
- `policy_scope` uses distinct to avoid duplicates

### Notes for Phase 3+ Development

1. Always call `authorize @resource` before responding
2. Use `policy_scope(Model)` for index actions
3. Check `user.in_organization?(org)` for org context
4. Remember: organization boundary checks in both policy AND query
5. Test both positive (authorized) and negative (denied) cases
6. Session-based org switching works in controllers with `current_organization=`
7. Remember that scope restriction is first, action permission is second
