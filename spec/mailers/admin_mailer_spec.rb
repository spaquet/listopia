require "rails_helper"

RSpec.describe AdminMailer, type: :mailer do
  describe "#user_invitation" do
    let(:user) { create(:user, email: "newadmin@example.com") }
    let(:token) { "test_token_123" }
    let(:mail) { described_class.user_invitation(user, token).deliver_now }

    it "sends email to the user" do
      expect { mail }.to change { ActionMailer::Base.deliveries.count }.by(1)
    end

    it "sets the correct recipient" do
      expect(mail.to).to eq([ user.email ])
    end

    it "sets the correct subject" do
      expect(mail.subject).to eq("Welcome to Listopia - Set Your Password")
    end

    it "includes the user in the email body" do
      expect(mail.body.encoded).to include(user.name)
    end

    it "sets the correct from address" do
      expect(mail.from).to eq([ "noreply@listopia.com" ])
    end

    it "passes the token to the setup URL" do
      expect(mail.body.encoded).to include(token)
    end

    it "includes a valid setup URL" do
      expect(mail.body.encoded).to match(/setup.*password|password.*setup/)
    end
  end
end
