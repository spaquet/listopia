# app/mailers/collaboration_mailer.rb
class CollaborationMailer < ApplicationMailer
  # Notify user they've been added to a list
  def added_to_list(collaboration)
    @collaboration = collaboration
    @user = collaboration.user
    @list = collaboration.list
    @inviter = @list.owner
    @list_url = list_url(@list)

    mail(
      to: @user.email,
      subject: "You've been added to \"#{@list.title}\""
    )
  end

  # Send invitation to non-registered user
  def invitation(email, list, inviter, token)
    @email = email
    @list = list
    @inviter = inviter
    @signup_url = new_registration_url
    @accept_url = accept_collaborations_url(token: token)

    mail(
      to: email,
      subject: "#{inviter.name} invited you to collaborate on \"#{list.title}\""
    )
  end

  # Notify user they've been removed from a list
  def removed_from_list(user, list)
    @user = user
    @list = list

    mail(
      to: user.email,
      subject: "You've been removed from \"#{list.title}\""
    )
  end
end
