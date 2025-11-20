# Organizations & Teams Feature

**Status**: Ready for AI Implementation  
**Framework**: Rails 8.1 | **Auth**: Rails 8 + Pundit + Rolify | **Audit**: Logidze

---

## 1. Overview

Add Organizations and Teams to Listopia by reusing existing infrastructure:

- **Reuse**: Invitations table (add org_id), Collaborators model (add validation), Logidze (enable on models), Mail templates (extend)
- **Create**: Organization, OrganizationMembership, Team, TeamMembership models
- **Key Rule**: Every user must belong to an organization; auto-create on signup

---

## 2. Data Model Changes

### New Models to Create

| Model | Purpose | Key Attributes |
|-------|---------|-----------------|
| Organization | Container for users/teams/lists | id, name, slug (unique), size (enum), status (enum), created_by FK |
| OrganizationMembership | User-org relationship | organization_id FK, user_id FK, role (enum: member/admin/owner), status (enum: pending/active/suspended/revoked), joined_at |
| Team | Sub-group within org | id, organization_id FK, name, slug, created_by FK |
| TeamMembership | User-team relationship | team_id FK, user_id FK, organization_membership_id FK, role (enum: member/lead/admin), joined_at |

**Constraints & Indices**:
- Organizations: UNIQUE(slug)
- OrganizationMembership: UNIQUE([organization_id, user_id]), UNIQUE(organization_id) per owner role
- Team: UNIQUE([organization_id, slug])
- TeamMembership: UNIQUE([team_id, user_id])
- TeamMembership: user must be member of organization first

**Enable Logidze**:
- Add `has_logidze` to Organization, OrganizationMembership, Team, TeamMembership

### Existing Models to Extend

| Model | Changes |
|-------|---------|
| User | Add: current_organization_id (FK, nullable), associations: has_many :organizations (through memberships), has_many :teams (through memberships) |
| List | Add: organization_id (FK, nullable), team_id (FK, nullable). Add scopes: by_organization, for_team. After save: sync organization_id from team if team present |
| Invitation | Add: organization_id (FK, nullable). Validate: organization_id matches invitable resource's org |
| Collaborator | Add validation: collaborator must be in same organization as collaboratable resource |

### Migration Strategy

**Do NOT create separate migrations** for existing models:

1. Find existing migration files for User, List, Invitation tables
2. Add new columns/indices to their create_table blocks
3. Create console script (db/seeds/filename.rb) for data population
4. Run migrations normally, then run console scripts

Example structure:
```
db/migrate/[existing_users_migration].rb 
  → Add current_organization_id column

db/migrate/[existing_lists_migration].rb 
  → Add organization_id, team_id columns

db/migrate/[existing_invitations_migration].rb 
  → Add organization_id column

db/seeds/migrate_users_to_organizations.rb
  → Script to create personal org for each user

db/seeds/migrate_lists_to_organizations.rb
  → Script to assign lists to user's default org
```

---

## 3. Authorization & Access Control

### Policies to Create

Create two new policy classes following existing ListPolicy pattern:

- **OrganizationPolicy**: show?, update?, destroy?, invite_member?, manage_teams?, view_audit_logs?
  - Scope: users.organizations (only orgs user is member of)
  
- **TeamPolicy**: show?, update?, destroy?, manage_members?
  - Scope: Team.joins(:organization).where(organizations: {id: user.organizations.select(:id)})

### Policy Integration Rules

1. Every controller action accessing org/team data must call `authorize @resource`
2. Every query must use `policy_scope(Model)` or explicit org filtering
3. ListPolicy must be updated: add check `user.in_organization?(record.organization)` to show?, update?, etc.
4. All scopes must include org boundary: `User.joins(:organizations).where(...)`

### Roles Configuration

Use existing Rolify pattern:
- Organization roles: member (default), admin, owner
- Team roles: member (default), lead, admin
- Store in OrganizationMembership.role and TeamMembership.role enums

---

## 4. Reusing Existing Infrastructure

### Invitations Table Extension

The existing Invitation model is polymorphic and already supports:
- invitable_type: "List", "ListItem", now add "Organization"
- Token-based acceptance via Rails 8's generates_token_for
- Permission and granted_roles fields

**To reuse for organizations**:
1. Add organization_id column to invitations table (in existing migration)
2. When creating org invitation, set invitable_type: "Organization", invitable_id: org.id, organization_id: org.id
3. Validation: organization_id must match invitable resource's organization
4. Org invitation acceptance creates OrganizationMembership instead of Collaborator

### Collaborators Validation Extension

The existing Collaborator model validates ownership:

**To extend for org scoping**:
1. Add validation: collaborator user must be in same organization as collaboratable resource
2. No schema changes needed, only model validation logic

### Logidze Audit Integration

Logidze already exists and automatically tracks changes:

**To enable on new models**:
1. Add `has_logidze` declaration in Organization, OrganizationMembership, Team, TeamMembership models
2. No additional configuration or tables needed
3. Access history via model.log_data and model.at(timestamp)

### Mail Template Reuse

CollaborationMailer already has templates. **To extend**:
1. Add org_invitation method to existing CollaborationMailer
2. Create template: app/views/collaboration_mailer/org_invitation.html.erb
3. Reuse existing email structure and styling

---

## 5. Implementation Phases

### Phase 1: Core Infrastructure (Weeks 1-2)

**Deliverables**:
1. Create migrations:
   - CreateOrganizations
   - CreateOrganizationMemberships
   - CreateTeams
   - CreateTeamMemberships
   - Update existing User migration: add current_organization_id
   - Update existing List migration: add organization_id, team_id
   - Update existing Invitation migration: add organization_id

2. Create models: Organization, OrganizationMembership, Team, TeamMembership with:
   - Associations to other models
   - Enum definitions
   - Validations (uniqueness, presence, org boundaries)
   - Logidze declarations

3. Update existing models:
   - User: add associations, add current_organization helper method, add in_organization?(org) method
   - List: add associations, add scopes for org/team filtering, add after_save hook to sync org_id from team
   - Invitation: add organization_id association, add org validation
   - Collaborator: add org boundary validation

4. Create console script: db/seeds/migrate_users_to_organizations.rb
   - Creates personal organization for each existing user
   - Creates OrganizationMembership as owner
   - Sets current_organization_id

5. Tests:
   - Model validations and associations
   - Migration data integrity
   - Enum definitions

**Instructions for AI Agent**:
- Review existing List and User models as reference for patterns
- Create migrations by modifying existing files, not creating new ones
- Add validations matching existing patterns (see Collaborator model for reference)
- Test all associations work correctly
- Run data migration script after migrations

### Phase 2: Authorization & Policies (Weeks 2-3)

**Deliverables**:
1. Create OrganizationPolicy and TeamPolicy
   - Follow ListPolicy as reference for structure
   - Implement resolve method to scope queries to user's organizations/teams
   - All action methods check policy

2. Update ApplicationController:
   - Add current_organization helper
   - Add set_current_organization method
   - Add before_action to require organization access
   - Handle session-based org switching

3. Update existing policies:
   - ListPolicy: add organization boundary check
   - UserPolicy: scope users by shared organizations

4. Tests:
   - Policy authorization tests (all scenarios)
   - Cross-org access denial
   - Session org switching

**Instructions for AI Agent**:
- Copy ListPolicy structure but adapt for org/team
- Check current_user.in_organization?(record) in each policy action
- Use policy_scope in resolve method
- Test both positive (authorized) and negative (denied) cases

### Phase 3: Admin Interface (Weeks 3-4)

**Deliverables**:
1. Create admin pages for:
   - Organizations index (list, search, filter)
   - Organization show (details, members, teams)
   - Members management (add, update role, remove)
   - Invite members (form)
   - Audit logs viewer
   - Suspend/delete organization

2. Update admin user management:
   - Filter users by organization
   - Show only users in current admin's organization

3. Real-time updates via Turbo Streams (follow existing List/ListItem patterns)

4. Tests:
   - Authorization on admin pages
   - Form submissions
   - Error handling

**Instructions for AI Agent**:
- Reference existing admin pages in codebase for patterns
- Scope all queries to @current_organization
- Use existing Turbo Stream patterns from ListsController
- Add Pundit authorization checks

### Phase 4: User Settings & Team Management (Weeks 4-5)

**Deliverables**:
1. Settings pages:
   - Organization switcher
   - Team creation form
   - Team listing
   - Team member management (add/remove)
   - Team role updates

2. Real-time updates via Turbo Streams

3. Tests:
   - Team CRUD operations
   - Member permission checks
   - Team isolation (can't access other org's teams)

**Instructions for AI Agent**:
- Build Settings section following existing pattern
- Use Turbo Streams for real-time updates
- Enforce team members must be org members first
- Add Pundit authorization

### Phase 5: Invitations & Onboarding (Weeks 5-6)

**Deliverables**:
1. OrganizationInvitationService:
   - Invite by email (registered and unregistered users)
   - Acceptance workflow
   - Auto-accept on signup if email matches

2. Updated signup flow:
   - Auto-create personal organization
   - Support signup with org invitation link

3. Email templates via CollaborationMailer:
   - org_invitation method
   - org_invitation.html.erb template

4. Tests:
   - Invitation creation
   - Acceptance flow
   - Token validation
   - Email delivery

**Instructions for AI Agent**:
- Create service class following InvitationService pattern
- Add method to CollaborationMailer (don't create separate mailer)
- Create email template reusing existing collaboration template structure
- Update Registrations controller to create org on signup
- Handle invitation token in signup flow

### Phase 6: List & Collaborators Scoping (Weeks 6-7)

**Deliverables**:
1. Update List queries to always filter by organization
2. Update Collaborators:
   - Add org boundary validation
   - Update InvitationService to set organization_id
3. Update ListPolicy: check org membership
4. Tests:
   - Cross-org access denial
   - Collaborator org validation

**Instructions for AI Agent**:
- Add validation to Collaborator model
- Update ListPolicy resolve to include org filtering
- Ensure all list queries use policy_scope or explicit org filtering
- Test that org boundary prevents cross-org collaboration

### Phase 7: Admin User Management Updates (Weeks 7-8)

**Deliverables**:
1. Update admin interface "Manage Users":
   - Add organization filter
   - Show only org users
   - Invite users to org
   - Remove users from org
2. Tests:
   - Admin can't see users outside org
   - Proper authorization

**Instructions for AI Agent**:
- Find existing admin user management pages
- Add org context/filtering
- Update queries to scope users by org
- Add authorization checks

### Phase 8: Final Integration & Testing (Weeks 8-9)

**Deliverables**:
1. Performance optimization:
   - Add indices on foreign keys
   - Eliminate N+1 queries
2. Edge case handling:
   - Org deletion with active lists
   - User removal from org
   - Org suspension
3. Documentation review
4. Full integration tests

**Instructions for AI Agent**:
- Profile queries for N+1 issues
- Add indices to migration files
- Write integration tests covering full workflows
- Test edge cases and error scenarios

---

## 6. Workflows & Access Control Patterns

### Signup Flow
1. User registers
2. Personal Organization auto-created
3. OrganizationMembership created (owner role)
4. current_organization_id set
5. User can create lists immediately

### Org Invitation Flow (Registered User)
1. Admin invites user@example.com
2. If user exists: OrganizationMembership created (status: pending)
3. User notified via email
4. User accepts in Settings
5. Membership status: active

### Org Invitation Flow (Unregistered User)
1. Admin invites user@example.com
2. If user doesn't exist: Invitation created
3. Signup link sent in email
4. User signs up with matching email
5. Invitation auto-accepted
6. OrganizationMembership created (status: active)

### Team Creation Flow
1. Org member navigates to Settings
2. Creates team with name
3. Adds existing org members to team
4. Each member becomes TeamMembership
5. Team can now be assigned to lists

### List Collaboration Within Org
1. List owner invites collaborator
2. System checks if email is org member
3. If yes: Collaborator created directly
4. If no: Invitation created (must sign up or join org)
5. On acceptance: Collaborator record created with permissions

### Access Control in Requests
Every request goes through:
1. Authentication (user exists)
2. Org membership (user in org)
3. Pundit authorization (policy checks)
4. Query scoping (data filtered)
5. Response (only accessible data returned)

If any layer fails: 403 Forbidden or 404 Not Found

---

## 7. Implementation Notes for AI Agents

### When Implementing a Feature
1. Identify what organization/team context it needs
2. Add org_id field to any new models
3. Create/update Pundit policies with org checks
4. Scope all queries to org via policy_scope or .where(organization_id: ...)
5. Test that cross-org access is denied

### When Creating Models
1. Add organization_id (FK) if scoped to org
2. Add associations to Organization/Team
3. Enable has_logidze for audit trail
4. Add validations for org boundaries

### When Updating Existing Models
1. Modify existing migration (don't create new one)
2. Create console script for data migration
3. Add org validation if needed
4. Test data integrity after migration

### When Writing Policies
1. Check user.in_organization?(record.organization) in actions
2. Implement resolve method with org filtering
3. Use scope to restrict visible records
4. Test both authorized and denied cases

---

## 8. Key Implementation Rules for AI Agents

### Rule 1: Org Boundary in Every Query
Every database query must filter by organization. If not using policy_scope:
- Add .where(organization_id: current_user.organizations.select(:id))
- Or access through association: current_organization.lists

### Rule 2: Authorization on Every Action
Every controller action accessing org/team data must:
- Call authorize @resource (for Pundit check)
- Or check user.in_organization?(resource.organization) explicitly

### Rule 3: Model Validation for Org Boundaries
Add validations to models that reference other resources:
- Collaborator validates user is in same org
- TeamMembership validates user is org member first
- Invitation validates organization_id matches resource

### Rule 4: Reuse Don't Duplicate
- Don't create new invitation table → extend existing
- Don't create new audit system → enable has_logidze
- Don't create new mailer → add method to CollaborationMailer
- Don't create new roles table → use existing Rolify

### Rule 5: Session-Based Context
- Store current_organization_id in session
- Provide helper method current_organization
- All queries implicitly use current org unless accessing admin functions

---

## 9. Test Coverage Requirements

For each phase, achieve:
- Model tests: validations, associations, scopes, before/after hooks
- Policy tests: positive (authorized) and negative (denied) scenarios
- Integration tests: full workflows from signup through collaboration
- Edge cases: resource deletion, user removal, status changes

Focus on authorization boundaries: core test is that user cannot access org they don't belong to.

---

## 10. Data Integrity Validation

After each phase, verify:
- All records have required FK relationships
- No orphaned records
- Org boundaries not violated
- Logidze properly tracking changes
- Session context works correctly
- Policies enforce boundaries at query level

---

## 11. Error Handling & User Experience

Provide clear error messages when:
- User not in organization (403 Forbidden)
- Resource in different org (404 Not Found or 403 Forbidden)
- Invalid role assignment (validation error)
- Org boundary violation (validation error)

---

## 12. Performance Considerations

- Index all foreign keys (organization_id, team_id, etc.)
- Use includes/joins to prevent N+1 queries
- Cache current_organization lookup if needed
- Profile Logidze queries with large histories

---

## 13. Transition Checklist

**Before considering implementation complete:**
- [ ] All 8 phases completed
- [ ] 100% policy test coverage
- [ ] Cross-org access denied at all layers
- [ ] No N+1 queries
- [ ] Logidze tracking all changes
- [ ] Mail templates working
- [ ] Session context working
- [ ] CLAUDE.md updated with all sections
- [ ] Data migration scripts run successfully
- [ ] Edge cases documented and tested
- [ ] No code duplication (all reuse patterns)
- [ ] Ready for gradual user rollout