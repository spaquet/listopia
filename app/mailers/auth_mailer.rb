# app/mailers/auth_mailer.rb
class AuthMailer < ApplicationMailer
  # Send magic link for passwordless authentication
  def magic_link(user, token)
    @user = user
    @token = token
    @login_url = authenticate_magic_link_url(token: token)

    mail(
      to: user.email,
      subject: "Your Listopia Magic Link"
    )
  end

  # Send email verification link
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
