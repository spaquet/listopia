# app/mailers/auth_mailer.rb
class AuthMailer < ApplicationMailer
  # Send magic link for passwordless authentication
  def magic_link(user, magic_link)
    @user = user
    @magic_link = magic_link
    @login_url = authenticate_magic_link_url(token: magic_link.token)

    mail(
      to: user.email,
      subject: "Your Listopia Magic Link"
    )
  end

  # Send email verification link
  def email_verification(user)
    @user = user
    @verification_url = verify_email_token_url(token: user.email_verification_token)

    mail(
      to: user.email,
      subject: "Verify your Listopia account"
    )
  end
end
