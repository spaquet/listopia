# Authentication & Authorization

Listopia uses **Rails 8 built-in authentication** with `has_secure_password` combined with **custom magic link functionality** for passwordless sign-in. Authorization is handled via [Pundit](./README.md#authorization--roles) policies and [Rolify](./README.md#authorization--roles) roles.

## Authentication Methods

### 1. Password-Based Sign In

```ruby
# User signs up
POST /sign_up
POST /verify_email/:token  # Email verification required

# User signs in
POST /sign_in (email, password)
```

**Flow:**
1. User registers with email/password
2. Verification email sent (expires in 24 hours)
3. User clicks verification link
4. Email verified, user can sign in
5. Password hashed with bcrypt (never stored)

### 2. Magic Link Authentication

```ruby
# User requests magic link (no password needed)
POST /magic_link (email)

# Clicks link in email
GET /authenticate/:token  # Auto signs in user
```

**Features:**
- Passwordless sign-in experience
- Tokens expire in 15 minutes
- Single-use tokens
- Ideal for first-time visitors and mobile users

## Token System

Listopia uses **Rails 8's `generates_token_for`** for secure, time-limited tokens:

```ruby
# app/models/user.rb
class User < ApplicationRecord
  has_secure_password

  # Generate time-limited, cryptographically-signed tokens
  generates_token_for :magic_link, expires_in: 15.minutes
  generates_token_for :email_verification, expires_in: 24.hours

  # Find user by token (validates signature, expiration)
  User.find_by_token_for(:magic_link, token)
  User.find_by_token_for(:email_verification, token)
end
```

### Token Security

- **Cryptographic signing** - Rails verifier prevents tampering
- **Automatic expiration** - Time-based validation, no database cleanup needed
- **Single-use** - Each token usage is a one-time event
- **Domain-scoped** - Tokens bound to application domain

See [User model](../app/models/user.rb) for implementation.

## Session Management

### Session Helpers

Available in all controllers via [ApplicationController](../app/controllers/application_controller.rb):

```ruby
# Checking authentication
user_signed_in?              # => true/false
current_user                 # => User instance or nil
authenticate_user!           # => redirect unless signed in
require_verified_email!      # => redirect unless email verified

# Sign in / Sign out
sign_in(user)
sign_out
```

### Session Configuration

- Sessions stored in Rails cache (via Solid Cache in production)
- CSRF protection automatic on all POST/PATCH/DELETE requests
- HttpOnly cookies prevent XSS access
- Secure cookies in production (HTTPS only)

## Email Integration

Emails sent via [AuthMailer](../app/mailers/auth_mailer.rb):

```ruby
# Magic link email
AuthMailer.magic_link(user, token).deliver_now
# Email link: https://your-domain.com/authenticate/:token

# Verification email
AuthMailer.email_verification(user, token).deliver_now
# Email link: https://your-domain.com/verify_email/:token
```

Configure SMTP in `config/environments/production.rb`:

```ruby
config.action_mailer.smtp_settings = {
  address: ENV.fetch("SMTP_ADDRESS"),
  port: ENV.fetch("SMTP_PORT"),
  user_name: ENV.fetch("SMTP_USERNAME"),
  password: ENV.fetch("SMTP_PASSWORD"),
  domain: ENV.fetch("SMTP_DOMAIN"),
  authentication: "plain"
}
```

## Collaboration Invitation Flow

When users receive collaboration invitations via email:

```
Guest clicks invitation link
  ↓
Invitation token stored in session
  ↓
Guest signs up or signs in
  ↓
System auto-accepts invitation (if email matches)
  ↓
User redirected to shared list
```

Implementation in [SessionsController](../app/controllers/sessions_controller.rb):

```ruby
def create
  # ... authenticate user ...
  redirect_path = check_pending_collaboration || dashboard_path
  redirect_to redirect_path
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

## Admin User Invitation Flow

Admins can create users directly via the admin interface or AI chat. New admin-created users receive a **password setup email** with a time-limited verification link.

### Creation Methods

**1. Admin Interface** - `POST /admin/users`
```ruby
# Admin creates user with optional admin role
Admin::UsersController.create(
  name: "John Doe",
  email: "john@example.com",
  make_admin: true  # Optional
)
```

**2. AI Chat** - `POST /chats/:id/messages`
```ruby
# AI chat can create users via tool calls
@chat.messages.create!(
  role: "user",
  content: "Create a user named Sarah with email sarah@example.com"
)
# System calls create_user tool via MCP
```

### Admin Invitation Flow

```
Admin creates user
  ↓
User.invited_by_admin = true (marked as admin-created)
User.email_verified_at = Time.current (pre-verified)
  ↓
AdminMailer.user_invitation email sent
  ↓
Email contains password setup link with token
  ↓
User clicks link → setup_password page
  ↓
User sets their own password
  ↓
User account fully activated
```

### Implementation

User model ([app/models/user.rb](../app/models/user.rb)):

```ruby
class User < ApplicationRecord
  # Flag for admin-created users
  # t.boolean :invited_by_admin, default: false

  def send_admin_invitation!
    # Mark as admin-created
    self.invited_by_admin = true
    self.save!

    # Generate verification token for password setup
    token = generate_email_verification_token
    
    # Send invitation email with password setup link
    AdminMailer.user_invitation(self, token).deliver_later
  end
end
```

Registrations controller ([app/controllers/registrations_controller.rb](../app/controllers/registrations_controller.rb)):

```ruby
class RegistrationsController < ApplicationController
  # Display password setup page
  def setup_password
    @user = User.find_by_token_for(:email_verification, params[:token])
    
    unless @user
      redirect_to new_registration_path, alert: "Invalid or expired setup link"
    end
  end

  # Complete password setup
  def complete_setup_password
    @user = User.find_by_token_for(:email_verification, params[:token])
    
    unless @user
      redirect_to new_registration_path, alert: "Invalid or expired setup link"
      return
    end

    if @user.update(password: params[:password], password_confirmation: params[:password_confirmation])
      sign_in(@user)
      redirect_to dashboard_path, notice: "Password set successfully! Welcome to Listopia."
    else
      render :setup_password, status: :unprocessable_entity
    end
  end
end
```

Routes ([config/routes.rb](../config/routes.rb)):

```ruby
# Admin user invitation setup
get "setup_password/:token", to: "registrations#setup_password", as: :setup_password_registration
post "setup_password/:token", to: "registrations#complete_setup_password"
```

### Key Features

- **Pre-verified emails** - Admin-created users skip email verification (already trusted)
- **Password setup, not reset** - Users set their initial password, not a temporary one
- **Audit trail** - `user.invited_by_admin` flag marks user as admin-created
- **Admin notes** - Admins can add notes about why user was created
- **AI-initiated creation** - Chat can create users with proper tool call handling
- **Role assignment** - Admins can grant admin role during creation

### Admin User Management

After user creation, admins can manage accounts:

```ruby
# Suspend user (sessions destroyed)
user.suspend!(reason: "Spam activity", suspended_by: current_user)

# Deactivate user (different from suspension)
user.deactivate!(reason: "Inactive", deactivated_by: current_user)

# Grant/revoke admin role
user.make_admin!
user.remove_admin!

# Update admin notes (for internal tracking)
user.update_admin_notes!("User is contractor for project X", updated_by: current_user)

# View audit trail
user.admin_audit_trail  # => Array of admin actions
```

## Collaboration Invitation Flow

When users receive collaboration invitations via email:

```
Guest clicks invitation link
  ↓
Invitation token stored in session
  ↓
Guest signs up or signs in
  ↓
System auto-accepts invitation (if email matches)
  ↓
User redirected to shared list
```

Implementation in [SessionsController](../app/controllers/sessions_controller.rb):

```ruby
def create
  # ... authenticate user ...
  redirect_path = check_pending_collaboration || dashboard_path
  redirect_to redirect_path
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

## Common Patterns

### Protecting Controller Actions

```ruby
class ListsController < ApplicationController
  before_action :authenticate_user!           # Must be signed in
  before_action :require_verified_email!      # Must verify email
  before_action :authorize_list_access        # Must have permission (Pundit)

  def show
    @list = List.find(params[:id])
    authorize @list  # Check Pundit policy
  end
end
```

### Accessing Current User

```ruby
# In controllers
current_user          # Current signed-in user
current_user.chats    # User's chats
current_user.lists    # User's lists

# In views
<% if user_signed_in? %>
  Welcome, <%= current_user.name %>!
<% end %>

# In models (via Current context)
Current.user          # Access from anywhere
```

### Password Updates

```ruby
def update_password
  if @user.authenticate(params[:current_password])
    if @user.update(password: params[:password])
      sign_in(@user)  # Re-sign in with new password
      redirect_to settings_user_path, notice: "Password updated"
    else
      flash.now[:alert] = "Password update failed"
      render :settings
    end
  else
    flash.now[:alert] = "Current password incorrect"
    render :settings
  end
end
```

## Testing Authentication

### Test Helpers

```ruby
# spec/support/authentication_helpers.rb
def sign_in_user(user = nil)
  user ||= create(:user, :verified)
  session[:user_id] = user.id
  user
end

def sign_out_user
  session.clear
end
```

### Authentication Tests

```ruby
describe "Sign in" do
  it "signs in user with valid credentials" do
    user = create(:user, :verified, password: "password123")
    
    post "/sign_in", params: {
      email: user.email,
      password: "password123"
    }
    
    expect(session[:user_id]).to eq(user.id)
    expect(response).to redirect_to(dashboard_path)
  end
end

describe "Magic link" do
  it "authenticates user via magic link token" do
    user = create(:user, :verified)
    token = user.generate_token_for(:magic_link)
    
    get "/authenticate/#{token}"
    
    expect(session[:user_id]).to eq(user.id)
  end
end
```

## Development Setup

### Email Testing

In development, emails are opened automatically via `letter_opener` gem:

```ruby
# config/environments/development.rb
config.action_mailer.delivery_method = :letter_opener
config.action_mailer.default_url_options = { 
  host: "localhost:3000" 
}
```

Emails open in your browser when sent. Check spam/mailers tab.

### Magic Links in Development

```ruby
# Generate test token in Rails console
user = User.find_by(email: "test@example.com")
token = user.generate_token_for(:magic_link)

# Test in browser
http://localhost:3000/authenticate/#{token}
```

## Production Checklist

- [ ] SSL/HTTPS enabled (`config.force_ssl = true`)
- [ ] SMTP configured with production mail provider
- [ ] Session store configured for production (Solid Cache)
- [ ] `config.action_mailer.default_url_options` set to production domain
- [ ] Environment variables set for SMTP credentials
- [ ] Email verification links use HTTPS URLs
- [ ] CSRF tokens included in all forms
- [ ] Secure cookies enabled in production

## Security Best Practices

1. **Always verify email before full access** - Prevent spam accounts
2. **Use HTTPS in production** - Encrypt auth tokens in transit
3. **Secure password hashing** - bcrypt never changes passwords unnecessarily
4. **Validate tokens on server** - Never trust client-side token validation
5. **Check authorization after authentication** - Pundit policies complement authentication
6. **Log auth failures** - Monitor for suspicious activity
7. **Expire sessions appropriately** - Balance security and UX

## Troubleshooting

**Magic links not working?**
- Check token generation: `user.generate_token_for(:magic_link)`
- Verify email delivery (check spam folder)
- Ensure URL includes correct domain
- Tokens expire in 15 minutes

**Email verification failing?**
- Check token expiration (24 hours)
- Verify email is reaching user inbox
- Tokens are single-use

**Sessions not persisting?**
- Ensure Solid Cache is running
- Check CSRF token in forms
- Verify session cookies enabled

See [CONTRIBUTING.md](./CONTRIBUTING.md) for development environment setup.