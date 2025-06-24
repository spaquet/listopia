# spec/support/authentication_helpers.rb
module AuthenticationHelpers
  # Helper to sign in a user for controller and request specs
  def sign_in_user(user = nil)
    user ||= create(:user, :verified)

    # For controller specs
    if respond_to?(:session)
      session[:user_id] = user.id
      session[:user_signed_in_at] = Time.current.to_s
    end

    user
  end

  # Helper to sign out current user
  def sign_out_user
    if respond_to?(:session)
      session.clear
    end
  end

  # Helper for system/feature specs using Capybara
  def sign_in_with_ui(user = nil)
    user ||= create(:user, :verified)

    visit new_session_path
    fill_in 'Email', with: user.email
    fill_in 'Password', with: user.password
    click_button 'Sign In'

    user
  end

  # Helper to create authenticated request headers
  def authenticated_headers(user = nil)
    user ||= create(:user, :verified)
    # For future API authentication
    { 'Authorization' => "Bearer #{user.auth_token}" }
  end

  # Current user helper for specs
  def current_user
    return nil unless session[:user_id]
    @current_user ||= User.find_by(id: session[:user_id])
  end
end
