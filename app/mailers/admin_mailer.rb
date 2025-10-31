# app/mailers/admin_mailer.rb
class AdminMailer < ApplicationMailer
  default from: "noreply@listopia.com"

  def user_invitation(user, token)
    @user = user
    @token = token
    @setup_url = setup_password_registration_url(token: token)

    mail(
      to: user.email,
      subject: "Welcome to Listopia - Set Your Password"
    )
  end
end
