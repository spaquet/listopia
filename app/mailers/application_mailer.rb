class ApplicationMailer < ActionMailer::Base
  default from: "from@example.com"
  layout "mailer"

  include Rails.application.routes.url_helpers

  def default_url_options
    { host: ENV.fetch("MAILER_HOST", "localhost:3000") }
  end
end
