# Phase 5: Invitations and Onboarding - Summary

## Overview
Phase 5 implements the complete invitation and onboarding system for organizations. This phase creates invitation service logic, email templates, and seamlessly integrates with the registration and email verification workflows.

## Files Created/Modified

### Services (New)

#### OrganizationInvitationService (`app/services/organization_invitation_service.rb`)
Service class for handling organization member invitations with email parsing and intelligent user handling:

**Key Features:**
- Flexible email parsing (comma or newline-separated strings or arrays)
- Intelligent user detection:
  - If user exists: creates membership directly (if not already member)
  - If user doesn't exist: creates invitation for later acceptance
- Results tracking: created invitations/memberships, already_member, invalid emails
- Bulk email validation before processing
- Email format validation with `URI::MailTo::EMAIL_REGEXP`

**Methods:**
- `invite_users`: Main entry point, returns results hash with created, already_member, invalid arrays
- `process_email(email)`: Processes individual email, creates membership or invitation
- `parse_emails(emails)`: Converts various formats to array of emails
- `create_membership(user)`: Creates OrganizationMembership for existing user
- `create_invitation(email)`: Creates Invitation record for new user

**Results Structure:**
```ruby
{
  created: [
    { email: "user@example.com", user_id: "uuid", name: "John Doe", type: "existing_user" },
    { email: "new@example.com", invitation_id: "uuid", type: "invitation" }
  ],
  already_member: [
    { email: "existing@example.com", user_id: "uuid", name: "Jane" }
  ],
  invalid: [
    { email: "bad-email", error: "Invalid email format" }
  ]
}
```

### Mailers (Modified)

#### CollaborationMailer (`app/mailers/collaboration_mailer.rb`)
Extended with organization-specific methods:

**New Methods:**
- `organization_invitation(membership_or_invitation)`: Router method that dispatches to appropriate handler based on type
- `handle_organization_membership_email(membership)`: Sends email to existing user added to organization
- `handle_organization_invitation_email(invitation)`: Sends email to new user invited to organization

**Template Variables:**
- For existing users: `@membership`, `@organization`, `@user`, `@inviter`, `@inviter_name`, `@organization_url`
- For new users: `@invitation`, `@organization`, `@email`, `@inviter`, `@inviter_name`, `@invitation_token`, `@signup_url`, `@accept_url`

### Email Templates (New)

#### HTML Email Template (`app/views/collaboration_mailer/organization_invitation.html.erb`)
Professional HTML email with:
- Header with organization name
- Contextual content for existing vs. new users
- Clear call-to-action buttons (Go to Organization, Accept Invitation, Sign Up)
- Fallback links with token
- Footer with legal notice
- Responsive design with inline CSS

#### Text Email Template (`app/views/collaboration_mailer/organization_invitation.text.erb`)
Plain text fallback with:
- Same content as HTML version
- Clickable links for accepting or signing up
- Professional formatting

### Controllers (Modified)

#### OrganizationMembersController (`app/controllers/organization_members_controller.rb`)
Updated to use the new invitation service:

**Changes:**
- `create` action now uses `OrganizationInvitationService` instead of manual logic
- Added `build_invitation_message(results)` helper to format user feedback
- Result message includes counts of sent invitations, already members, and invalid emails
- Flexible email input handling through service

**Updated Flow:**
```
1. Parse email input and role parameter
2. Initialize OrganizationInvitationService
3. Call invite_users to process invitations
4. Build result message with counts
5. Redirect with flash notice containing summary
```

#### OrganizationInvitationsController (`app/controllers/organization_invitations_controller.rb`)
Completely updated with invitation acceptance workflow:

**New Methods:**
- `accept`: Handles invitation acceptance with different flows for signed-in and new users
  - Validates invitation exists, not expired, and is pending
  - For signed-in users: checks email matches and accepts invitation
  - For new users: stores token in session and redirects to signup
- `accept_organization_invitation(invitation, user)`: Private method to finalize acceptance
  - Creates/updates organization membership (reactivates if suspended/revoked)
  - Marks invitation as accepted
  - Sets current_organization if user has none
  - Handles all in transaction for data integrity

**Updated Methods:**
- `resend`: Now sends email via `CollaborationMailer.organization_invitation`
- `initialize`: Skips authentication and org loading for `accept` action

**Acceptance Flow:**
```
1. User clicks invitation link (token in URL)
2. If signed in: verify email matches and accept
3. If not signed in: store token in session, redirect to signup
4. On email verification: auto-accept invitation, redirect to organization
5. Create membership with role from invitation metadata
6. Mark invitation as accepted
7. Set current_organization for user
```

#### RegistrationsController (`app/controllers/registrations_controller.rb`)
Integrated with organization system:

**New Features:**
- `create` action now auto-creates personal organization for new users via `create_personal_organization` helper
- Stores pending organization invitation token in session if present
- `verify_email` action checks for pending organization invitation token
- Auto-redirects to accept organization invitation after email verification

**New Helper Method - `create_personal_organization(user)`:**
- Creates personal organization with name: "{user.name}'s Workspace"
- Generates unique slug from email + first 8 chars of UUID
- Creates organization with owner role for creator
- Creates OrganizationMembership for user as owner
- Sets organization as user's current_organization

**Signup Flow with Organization Invitation:**
```
1. User clicks organization invitation link
2. If not signed in: stores token in session, redirects to signup
3. User signs up with email matching invitation
4. Personal org created automatically
5. Store org invitation token in session
6. Send email verification link
7. User clicks email verification
8. System auto-accepts org invitation
9. User redirected to organization with success message
```

### Routes (Modified)

#### New Route in `config/routes.rb`
```ruby
get "/organizations/invitations/accept/:token",
    to: "organization_invitations#accept",
    as: "accept_organization_invitation"
```
Public route allowing unauthenticated users to follow invitation links.

## Architecture & Design Patterns

### Invitation Workflow
```
EXISTING USER INVITATION:
1. Invite sent (service creates membership, sends email)
2. Email delivered with link to organization
3. User clicks link
4. Already member, sees organization

NEW USER INVITATION:
1. Invite sent (service creates invitation record, sends email)
2. Email delivered with signup link + invitation token
3. User clicks link (unauthenticated)
4. System stores token in session, redirects to signup
5. User signs up
6. Personal org created
7. Email verification sent
8. User verifies email
9. System auto-accepts organization invitation
10. User redirected to organization with welcome message
```

### Service Pattern Benefits
- Separation of concerns: business logic in service, not controller
- Reusable: can be called from controllers, jobs, console
- Testable: isolated logic with clear inputs/outputs
- Flexible email parsing: supports multiple input formats
- Intelligent user handling: optimizes for existing vs. new users

### Session-Based Token Management
- Tokens stored in session (temporary, secure)
- Tokens cleared after use to prevent reuse
- Follows Rails conventions for session security
- Works across signup → verification → acceptance flow

### Email Template Strategy
- Single template handles both user types (existing + new)
- Conditional rendering based on available variables
- HTML and text versions for email client compatibility
- Responsive design, accessible links

## Security Considerations

### Invitation Validation
- Token expires in 7 days (set by Invitation model)
- Status check ensures only pending invitations accepted
- Email verification required before acceptance
- Email must match invitation email
- User can only accept invitation for their email address

### Session Token Storage
- Tokens only stored in session (cleared after use)
- No tokens in URLs except in email links
- Email verification required before token used
- Prevents CSRF by requiring signed-in user for existing user flow

### Role Preservation
- Invitation metadata stores invited role
- Role applied when membership created
- User cannot change their own role without admin action

## Data Flow Examples

### Inviting Existing User
```
POST /organizations/:id/members
  params: { emails: "john@example.com", role: "admin" }

→ OrganizationInvitationService#invite_users
  1. Parse email
  2. Find user by email
  3. User exists: create_membership with admin role
  4. Send welcome email
  5. Return { created: [...], already_member: [], invalid: [] }

→ Flash: "1 invitation(s) sent"
→ Render members index
```

### Inviting New User
```
POST /organizations/:id/members
  params: { emails: "newuser@example.com", role: "member" }

→ OrganizationInvitationService#invite_users
  1. Parse email
  2. Find user by email
  3. User doesn't exist: create_invitation
  4. Send invitation email with accept link
  5. Return { created: [...], already_member: [], invalid: [] }

→ Flash: "1 invitation(s) sent"
→ Render members index
```

### Accepting Invitation (New User)
```
1. GET /organizations/invitations/accept/token123
   → New user: store token in session
   → Redirect to signup

2. POST /sign_up
   → User registers with matching email
   → create_personal_organization called
   → Email verification sent
   → Store org_invitation_token in session

3. GET /verify_email/verification_token
   → Email verified
   → Check for org_invitation_token in session
   → Redirect to accept_organization_invitation_path(org_token)
   → Sign in user

4. GET /organizations/invitations/accept/org_token
   → Accept invitation (now signed in)
   → Create/update membership
   → Mark invitation accepted
   → Redirect to organization_path with success message
```

## Testing Considerations

For integration tests, verify:
- [ ] Existing users get added immediately with email sent
- [ ] New users get invitation with email sent
- [ ] Invalid emails are reported in results
- [ ] Already members are identified correctly
- [ ] Personal organization created on signup
- [ ] Invitation tokens are cryptographically secure
- [ ] Token expiration enforced (7 days)
- [ ] Email address validation on acceptance
- [ ] Role from invitation metadata applied correctly
- [ ] Current organization set on acceptance
- [ ] Email verification required for new users
- [ ] Org tokens work across signup flow

## Files Summary

**Created:**
- `app/services/organization_invitation_service.rb` - Bulk invitation service
- `app/views/collaboration_mailer/organization_invitation.html.erb` - HTML email template
- `app/views/collaboration_mailer/organization_invitation.text.erb` - Text email template

**Modified:**
- `app/mailers/collaboration_mailer.rb` - Added org invitation methods
- `app/controllers/organization_members_controller.rb` - Use service for invitations
- `app/controllers/organization_invitations_controller.rb` - Complete acceptance flow
- `app/controllers/registrations_controller.rb` - Auto-create org, handle invitations
- `config/routes.rb` - Added invitation accept route

## Next Steps (Phase 6)

Phase 6 will implement list and collaborator scoping:
- Add organization_id to all list queries
- Filter lists by organization in policy scope
- Add organization boundary validation to collaborators
- Test cross-organization access denial
- Update list queries to filter by org

## Summary Statistics

- **Files Created**: 3 (service + 2 email templates)
- **Files Modified**: 5 (mailer, 3 controllers, routes)
- **Total Lines Added**: ~550+ lines
- **New Methods**: 8+ methods across controllers/services
- **Email Templates**: 2 (HTML + text)
- **Routes Added**: 1 public invitation accept route
- **Security Features**: Token expiration, email validation, role preservation
- **Invitation Types Supported**: Existing users, new users, bulk emails

## Code Quality Checklist

- [x] Service pattern for reusability
- [x] Flexible email parsing (string, array, comma/newline)
- [x] Comprehensive error handling
- [x] Transaction safety for acceptance
- [x] HTML + text email templates
- [x] Session token management
- [x] Security validation on acceptance
- [x] Email verification requirement
- [x] Personal org auto-creation
- [x] Cross-signup invitation flow
- [x] Role preservation in metadata
- [x] Current organization context management
- [x] Bulk operation result tracking
