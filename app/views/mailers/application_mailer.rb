# app/views/mailers/application_mailer.rb
class ApplicationMailer < ActionMailer::Base
  default from: "noreply@listopia.com"
  layout "mailer"
end
