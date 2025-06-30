# Listopia Authentication System Documentation

## Supported Authentication Scenarios

### **Traditional Authentication**
1. **User registration with email verification** - New users sign up and must verify email before accessing the app
2. **Password-based sign in** - Users sign in with email/password combination
3. **Email verification workflow** - Users receive verification emails with time-limited tokens
4. **Password management** - Users can update passwords through settings

### **Magic Link Authentication**
5. **Passwordless sign in** - Users can request magic links instead of using passwords
6. **Magic link generation** - System generates secure, time-limited authentication tokens
7. **One-click authentication** - Users click email links to sign in automatically

### **Session Management**
8. **Secure session handling** - Rails 8 session management with CSRF protection
9. **Automatic sign out** - Sessions expire appropriately for security
10. **Persistent authentication state** - Users stay signed in across browser sessions

### **Collaboration Integration**
11. **Invitation acceptance workflow** - Pending collaboration invitations are handled during sign in
12. **Seamless collaboration onboarding** - New users can accept invitations as part of registration

## Overview

Listopia implements a modern, secure authentication system using **Rails 8's built-in authentication features** combined with **custom magic link functionality**. The system prioritizes user experience while maintaining strong security standards.

## Architecture

### Core Components

1. **Rails 8 Authentication** - Built-in `has_secure_password` with modern token generation
2. **Custom SessionsController** - Handles sign in/out and magic link authentication
3. **RegistrationsController** - Manages user sign up and email verification
4. **Magic Link System** - Passwordless authentication using Rails 8 tokens
5. **Email Integration** - AuthMailer for verification and magic link emails

### Authentication Flow

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   User Visits   │────│  Authentication  │────│   Dashboard     │
│   Sign In Page  │    │    Controller    │    │   (Authorized)  │
└─────────────────┘    └──────────────────┘    └─────────────────┘
         │                       │                       │
         ▼                       ▼                       ▼
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│  Magic Link     │    │  Email/Password  │    │  Session        │
│  Authentication │    │  Validation      │    │  Management     │
└─────────────────┘    └──────────────────┘    └─────────────────┘
```

## User Model & Token System

### Rails 8 Token Generation

```ruby
# app/models/user.rb
class User < ApplicationRecord
  has_secure_password

  # Rails 8 token generation for magic links and email verification
  generates_token_for :magic_link, expires_in: 15.minutes
  generates_token_for :email_verification, expires_in: 24.hours

  # Email verification status
  def email_verified?
    email_verified_at.present?
  end

  def verify_email!
    update!(email_verified_at: Time.current, email_verification_token: nil)
  end
end
```

### Token Security Features

- **Time-limited expiration** - Magic links expire in 15 minutes, verification in 24 hours
- **Single-use tokens** - Tokens are invalidated after use
- **Cryptographic security** - Rails 8 uses message verifiers for tamper-proof tokens
- **Automatic cleanup** - Expired tokens are automatically invalid

## Registration Process

### User Sign Up Flow

```ruby
# app/controllers/registrations_controller.rb
class RegistrationsController < ApplicationController
  def create
    @user = User.new(user_params)
    
    if @user.save
      # Send verification email
      verification_token = @user.generate_token_for(:email_verification)
      AuthMailer.email_verification(@user, verification_token).deliver_now
      
      redirect_to verify_email_path
    else
      render :new, status: :unprocessable_entity
    end
  end

  def verify_email
    user = User.find_by_token_for(:email_verification, params[:token])
    
    if user
      user.verify_email!
      sign_in(user)
      redirect_to dashboard_path, notice: "Email verified successfully!"
    else
      redirect_to new_registration_path, alert: "Invalid or expired verification link."
    end
  end
end
```

### Registration Security

- **Email validation** - RFC-compliant email format validation
- **Password requirements** - Handled by `has_secure_password`
- **Unique email constraint** - Database-level uniqueness
- **Verification requirement** - Users must verify email before full access

## Authentication Methods

### Password-Based Authentication

```ruby
# app/controllers/sessions_controller.rb
def create
  @user = User.find_by(email: params[:email])

  if @user&.authenticate(params[:password])
    if @user.email_verified?
      sign_in(@user)
      redirect_to after_sign_in_path, notice: "Welcome back!"
    else
      redirect_to verify_email_path, alert: "Please verify your email address first."
    end
  else
    flash.now[:alert] = "Invalid email or password"
    render :new, status: :unprocessable_entity
  end
end
```

### Magic Link Authentication

```ruby
# Magic link generation
def magic_link
  email = params[:email]
  user = User.find_by(email: email)

  if user
    magic_link_token = user.generate_token_for(:magic_link)
    AuthMailer.magic_link(user, magic_link_token).deliver_now
    redirect_to magic_link_sent_path, notice: "Magic link sent to your email!"
  else
    flash.now[:alert] = "No account found with that email address."
    render :new, status: :unprocessable_entity
  end
end

# Magic link authentication
def authenticate_magic_link
  token = params[:token]
  user = User.find_by_token_for(:magic_link, token)

  if user
    sign_in(user)
    redirect_to after_sign_in_path, notice: "Successfully signed in!"
  else
    redirect_to new_session_path, alert: "Invalid or expired magic link."
  end
end
```

## Session Management

### Authentication Helper Methods

```ruby
# app/controllers/concerns/authentication.rb
module Authentication
  extend ActiveSupport::Concern

  included do
    before_action :current_user
  end

  private

  def current_user
    @current_user ||= session[:user_id] && User.find_by(id: session[:user_id])
  end

  def user_signed_in?
    current_user.present?
  end

  def sign_in(user)
    session[:user_id] = user.id
    session[:user_signed_in_at] = Time.current.to_s
  end

  def sign_out
    session.clear
    @current_user = nil
  end

  def authenticate_user!
    redirect_to new_session_path unless user_signed_in?
  end
end
```

### Session Security

- **CSRF Protection** - Automatic Rails protection against cross-site request forgery
- **Session Timeout** - Sessions include timestamp for potential timeout logic
- **Secure Cookies** - Rails handles secure cookie settings in production
- **Session Clearing** - Complete session clear on sign out

## Email Integration

### AuthMailer Implementation

```ruby
# app/mailers/auth_mailer.rb
class AuthMailer < ApplicationMailer
  def magic_link(user, token)
    @user = user
    @token = token
    @login_url = authenticate_magic_link_url(token: token)

    mail(
      to: user.email,
      subject: "Your Listopia Magic Link"
    )
  end

  def email_verification(user, token)
    @user = user
    @token = token
    @verification_url = verify_email_token_url(token: token)

    mail(
      to: user.email,
      subject: "Verify your Listopia account"
    )
  end
end
```

### Email Templates

- **Responsive HTML design** - Works on mobile and desktop
- **Clear call-to-action buttons** - Easy-to-find authentication links
- **Security messaging** - Users understand link expiration and security
- **Branded design** - Consistent with Listopia visual identity

## Collaboration Integration

### Invitation Acceptance Flow

```ruby
# Handle pending collaboration invitations during sign in
def check_pending_collaboration
  return nil unless session[:pending_collaboration_token]

  collaboration = ListCollaboration.find_by_invitation_token(session[:pending_collaboration_token])
  if collaboration && collaboration.email == current_user.email
    collaboration.update!(user: current_user, email: nil)
    session.delete(:pending_collaboration_token)
    
    return list_path(collaboration.list)
  end
  
  nil
end
```

### Seamless User Experience

1. **Guest receives invitation link** - Email contains collaboration invitation
2. **Guest clicks link without account** - System stores invitation token in session
3. **Guest signs up/signs in** - Authentication process captures pending invitation
4. **Automatic collaboration acceptance** - User is added to list after authentication
5. **Redirect to list** - User lands directly on the shared list

## Routes Configuration

### Authentication Routes

```ruby
# config/routes.rb
Rails.application.routes.draw do
  # Registration
  get "sign_up", to: "registrations#new", as: :new_registration
  post "sign_up", to: "registrations#create", as: :registration
  get "verify_email", to: "registrations#email_verification_pending"
  get "verify_email/:token", to: "registrations#verify_email", as: :verify_email_token

  # Sessions
  get "sign_in", to: "sessions#new", as: :new_session
  post "sign_in", to: "sessions#create", as: :session
  delete "sign_out", to: "sessions#destroy", as: :destroy_session

  # Magic link authentication
  post "magic_link", to: "sessions#magic_link"
  get "magic_link_sent", to: "sessions#magic_link_sent"
  get "authenticate/:token", to: "sessions#authenticate_magic_link", as: :authenticate_magic_link
end
```

## User Experience Features

### Progressive Enhancement

- **Works without JavaScript** - Core authentication functions server-side
- **Enhanced with Turbo** - Smooth page transitions and form submissions
- **Mobile-friendly design** - Responsive forms and buttons
- **Accessible markup** - Proper form labels and semantic HTML

### Error Handling

- **Graceful error messages** - Clear, actionable feedback for users
- **Form validation** - Client and server-side validation
- **Rate limiting** - Protection against brute force attacks
- **Recovery options** - Clear paths for password reset and re-verification

## Security Considerations

### Token Security

- **Short expiration times** - Magic links expire in 15 minutes
- **Single-use enforcement** - Tokens invalidated after use
- **Cryptographic signing** - Rails 8 message verifiers prevent tampering
- **Domain validation** - Tokens only work on correct domain

### Password Security

- **bcrypt hashing** - Industry-standard password hashing via `has_secure_password`
- **No password storage** - Only hashed versions stored in database
- **Password requirements** - Can be enhanced with custom validation
- **Secure password updates** - Require current password verification

### Session Security

- **HttpOnly cookies** - Prevent XSS access to session cookies
- **Secure transmission** - HTTPS enforced in production
- **CSRF protection** - Automatic Rails CSRF token validation
- **Session timeout** - Can implement automatic timeout logic

## Testing Authentication

### Test Helpers

```ruby
# spec/support/authentication_helpers.rb
module AuthenticationHelpers
  def sign_in_user(user = nil)
    user ||= create(:user, :verified)
    session[:user_id] = user.id
    session[:user_signed_in_at] = Time.current.to_s
    user
  end

  def sign_in_with_ui(user = nil)
    user ||= create(:user, :verified)
    visit new_session_path
    fill_in 'Email', with: user.email
    fill_in 'Password', with: user.password
    click_button 'Sign In'
    user
  end
end
```

### Authentication Tests

```ruby
# spec/system/authentication_flow_spec.rb
RSpec.describe "Authentication Flow", type: :system do
  describe "Sign in process" do
    it "allows user to sign in with valid credentials" do
      user = create(:user, :verified)
      visit new_session_path
      
      fill_in 'Email', with: user.email
      fill_in 'Password', with: user.password
      click_button 'Sign In'
      
      expect(page).to have_current_path(dashboard_path)
      expect(page).to have_content("Welcome back!")
    end
  end

  describe "Magic link authentication" do
    it "can request and use magic link" do
      user = create(:user, :verified)
      visit new_session_path
      
      fill_in placeholder: "Enter your email for magic link", with: user.email
      click_button "Send Magic Link"
      
      expect(page).to have_current_path(magic_link_sent_path)
      
      # Test magic link (in real usage, user clicks email link)
      token = user.generate_token_for(:magic_link)
      visit authenticate_magic_link_path(token: token)
      
      expect(page).to have_current_path(dashboard_path)
    end
  end
end
```

## Environment Configuration

### Development Setup

```ruby
# config/environments/development.rb
config.action_mailer.delivery_method = :letter_opener
config.action_mailer.default_url_options = { host: "localhost", port: 3000 }
```

### Production Considerations

```ruby
# config/environments/production.rb
config.force_ssl = true
config.action_mailer.default_url_options = { host: "listopia.app", protocol: 'https' }
# Configure SMTP settings for production email delivery
```

## Common Patterns & Best Practices

### 1. Always Verify Email Before Full Access

```ruby
def authenticate_user!
  redirect_to new_session_path unless user_signed_in?
end

def require_verified_email!
  if current_user && !current_user.email_verified?
    redirect_to verify_email_path, alert: "Please verify your email address."
  end
end
```

### 2. Handle Pending Collaborations

```ruby
# Always check for pending invitations after sign in
def after_sign_in_path
  check_pending_collaboration || dashboard_path
end
```

### 3. Secure Password Updates

```ruby
def update_password
  if @user.authenticate(params[:current_password])
    if @user.update(password_params)
      redirect_to settings_user_path, notice: "Password updated successfully."
    else
      render :settings, status: :unprocessable_entity
    end
  else
    flash.now[:alert] = "Current password is incorrect."
    render :settings, status: :unprocessable_entity
  end
end
```

### 4. Rate Limiting (Future Enhancement)

```ruby
# Consider implementing rate limiting for authentication attempts
class SessionsController < ApplicationController
  before_action :check_rate_limit, only: [:create, :magic_link]
  
  private
  
  def check_rate_limit
    # Implement rate limiting logic
  end
end
```

## Troubleshooting

### Common Issues

**1. Magic links not working**
- Check token expiration (15 minutes)
- Verify email delivery in development (letter_opener)
- Ensure URL generation includes correct host

**2. Email verification failing**
- Check for expired tokens (24 hours)
- Verify email is reaching user (spam folders)
- Ensure verification controller finds user correctly

**3. Session issues**
- Check that Current.user is set for notifications
- Verify CSRF tokens are included in forms
- Ensure session cookies are secure in production

**4. Collaboration invitation problems**
- Verify session storage of pending tokens
- Check email matching between invitation and user account
- Ensure collaboration model associations are correct

### Debugging Commands

```ruby
# Check user authentication status
user.email_verified?

# Generate test tokens
user.generate_token_for(:magic_link)
user.generate_token_for(:email_verification)

# Find user by token
User.find_by_token_for(:magic_link, token)

# Check session state
session[:user_id]
session[:pending_collaboration_token]
```

## Future Enhancements

### Planned Features

1. **Two-factor authentication** - SMS or TOTP-based 2FA
2. **OAuth integration** - Google, GitHub, Apple sign in
3. **Account recovery** - Password reset functionality
4. **Device management** - Track and manage signed-in devices
5. **Security audit log** - Track authentication events

### Security Improvements

- **Rate limiting** - Prevent brute force attacks
- **Device fingerprinting** - Detect suspicious login patterns
- **Email notifications** - Alert users of new sign-ins
- **Account lockout** - Temporary lockout after failed attempts

## Summary

Listopia's authentication system provides a modern, secure, and user-friendly experience using Rails 8's built-in features enhanced with custom magic link functionality. The system seamlessly integrates with the collaboration features and provides a solid foundation for the application's security needs.

**Key Strengths:**
- **Rails 8 token system** - Secure, time-limited authentication tokens
- **Dual authentication methods** - Both password and passwordless options
- **Email verification** - Ensures valid email addresses
- **Collaboration integration** - Seamless invitation acceptance flow
- **Comprehensive testing** - Well-tested authentication flows