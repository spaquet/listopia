require "rails_helper"

RSpec.describe CollaborationMailer, type: :mailer do
  describe "#invitation" do
    let(:inviter) { create(:user, name: "Alice Johnson") }
    let(:invitation) { create(:invitation, invited_by: inviter, email: "newcollaborator@example.com") }
    let(:mail) { described_class.invitation(invitation).deliver_now }

    it "sends email to the invitee" do
      expect { mail }.to change { ActionMailer::Base.deliveries.count }.by(1)
    end

    it "sets the correct recipient" do
      expect(mail.to).to eq([ invitation.email ])
    end

    it "includes inviter name in subject" do
      expect(mail.subject).to include(inviter.name)
    end

    it "includes invitable title in subject" do
      expect(mail.subject).to include(invitation.invitable.title)
    end

    it "sets the correct from address" do
      expect(mail.from).to eq([ "noreply@listopia.com" ])
    end

    it "includes invitation URL in body" do
      expect(mail.body.encoded).to match(/accept.*invitation/)
    end

    context "when inviter name is nil" do
      before do
        allow(invitation.invited_by).to receive(:name).and_return(nil)
      end

      it "uses 'Someone' as fallback name" do
        expect(mail.subject).to include("Someone invited you to collaborate")
      end
    end
  end

  describe "#invitation_reminder" do
    let(:inviter) { create(:user, name: "Bob Smith") }
    let(:invitation) { create(:invitation, invited_by: inviter) }
    let(:mail) { described_class.invitation_reminder(invitation).deliver_now }

    it "sends email to the invitee" do
      expect { mail }.to change { ActionMailer::Base.deliveries.count }.by(1)
    end

    it "sets the correct recipient" do
      expect(mail.to).to eq([ invitation.email ])
    end

    it "includes reminder text in subject" do
      expect(mail.subject).to include("Reminder")
    end

    it "includes invitable title in subject" do
      expect(mail.subject).to include(invitation.invitable.title)
    end

    it "includes acceptance URL" do
      expect(mail.body.encoded).to match(/accept.*invitation/)
    end

    it "includes signup URL for new users" do
      expect(mail.body.encoded).to match(/sign.*up|register/)
    end

    context "when invitable is a ListItem" do
      let(:list) { create(:list) }
      let(:list_item) { create(:list_item, list: list) }
      let(:invitation) { create(:invitation, invitable: list_item, invited_by: inviter) }

      it "uses the list in the template context" do
        expect(mail.body.encoded).to include(list.title)
      end
    end
  end

  describe "#added_to_resource" do
    let(:user) { create(:user) }
    let(:collaborator) { create(:collaborator, user: user) }
    let(:mail) { described_class.added_to_resource(collaborator).deliver_now }

    it "sends email to the collaborator user" do
      expect { mail }.to change { ActionMailer::Base.deliveries.count }.by(1)
    end

    it "sets the correct recipient" do
      expect(mail.to).to eq([ user.email ])
    end

    it "includes resource title in subject" do
      expect(mail.subject).to include(collaborator.collaboratable.title)
    end

    it "sets the correct from address" do
      expect(mail.from).to eq([ "noreply@listopia.com" ])
    end

    it "includes resource URL in body" do
      expect(mail.body.encoded).to match(%r{/lists/#{collaborator.collaboratable.id}})
    end
  end

  describe "#removed_from_resource" do
    let(:user) { create(:user) }
    let(:list) { create(:list) }
    let(:mail) { described_class.removed_from_resource(user, list).deliver_now }

    it "sends email to the user" do
      expect { mail }.to change { ActionMailer::Base.deliveries.count }.by(1)
    end

    it "sets the correct recipient" do
      expect(mail.to).to eq([ user.email ])
    end

    it "includes resource title in subject" do
      expect(mail.subject).to include(list.title)
    end

    it "sets the correct from address" do
      expect(mail.from).to eq([ "noreply@listopia.com" ])
    end
  end

  describe "#permission_updated" do
    let(:user) { create(:user) }
    let(:collaborator) { create(:collaborator, user: user, permission: :write) }
    let(:mail) { described_class.permission_updated(collaborator, :read).deliver_now }

    it "sends email to the collaborator user" do
      expect { mail }.to change { ActionMailer::Base.deliveries.count }.by(1)
    end

    it "sets the correct recipient" do
      expect(mail.to).to eq([ user.email ])
    end

    it "includes resource title in subject" do
      expect(mail.subject).to include(collaborator.collaboratable.title)
    end

    it "includes permission change in body" do
      expect(mail.body.encoded).to include("permission")
    end

    it "includes resource URL in body" do
      expect(mail.body.encoded).to match(%r{/lists/#{collaborator.collaboratable.id}})
    end

    it "includes old and new permission information" do
      expect(mail.body.encoded).to match(/read|write|Read|Write/i)
    end
  end

  describe "#organization_invitation with OrganizationMembership" do
    let(:organization) { create(:organization) }
    let(:user) { create(:user) }
    let(:membership) { create(:organization_membership, organization: organization, user: user) }
    let(:mail) { described_class.organization_invitation(membership).deliver_now }

    it "sends email to the user" do
      expect { mail }.to change { ActionMailer::Base.deliveries.count }.by(1)
    end

    it "sets the correct recipient" do
      expect(mail.to).to eq([ user.email ])
    end

    it "includes organization name in subject" do
      expect(mail.subject).to include(organization.name)
    end

    it "includes organization creator name in subject" do
      expect(mail.subject).to include(organization.creator.name)
    end

    it "includes organization URL in body" do
      expect(mail.body.encoded).to match(%r{/organizations/#{organization.id}})
    end
  end

  describe "#organization_invitation with Invitation" do
    let(:organization) { create(:organization) }
    let(:inviter) { create(:user, name: "Org Admin") }
    let(:invitation) do
      create(:invitation,
             email: "newmember@example.com",
             organization: organization,
             invited_by: inviter)
    end
    let(:mail) { described_class.organization_invitation(invitation).deliver_now }

    it "sends email to the invitee" do
      expect { mail }.to change { ActionMailer::Base.deliveries.count }.by(1)
    end

    it "sets the correct recipient" do
      expect(mail.to).to eq([ invitation.email ])
    end

    it "includes organization name in subject" do
      expect(mail.subject).to include(organization.name)
    end

    it "includes inviter name in subject" do
      expect(mail.subject).to include(inviter.name)
    end

    it "includes signup URL for new users" do
      expect(mail.body.encoded).to match(/sign.*up|register/)
    end

    it "includes acceptance URL" do
      expect(mail.body.encoded).to match(/accept.*invitation/)
    end
  end

  describe "#team_member_invitation with TeamMembership" do
    let(:team) { create(:team) }
    let(:user) { create(:user) }
    let(:membership) { create(:team_membership, team: team, user: user) }
    let(:mail) { described_class.team_member_invitation(membership).deliver_now }

    it "sends email to the user" do
      expect { mail }.to change { ActionMailer::Base.deliveries.count }.by(1)
    end

    it "sets the correct recipient" do
      expect(mail.to).to eq([ user.email ])
    end

    it "includes team name in subject" do
      expect(mail.subject).to include(team.name)
    end

    it "includes organization name in subject" do
      expect(mail.subject).to include(team.organization.name)
    end

    it "includes team creator name in subject" do
      expect(mail.subject).to include(team.creator.name)
    end

    it "includes team URL in body" do
      expect(mail.body.encoded).to match(%r{/organizations/#{team.organization.id}/teams/#{team.id}})
    end
  end

  describe "#team_member_invitation with Invitation" do
    let(:team) { create(:team) }
    let(:inviter) { create(:user, name: "Team Lead") }
    let(:invitation) do
      create(:invitation,
             email: "newteammember@example.com",
             invitable: team,
             organization: team.organization,
             invited_by: inviter)
    end
    let(:mail) { described_class.team_member_invitation(invitation).deliver_now }

    it "sends email to the invitee" do
      expect { mail }.to change { ActionMailer::Base.deliveries.count }.by(1)
    end

    it "sets the correct recipient" do
      expect(mail.to).to eq([ invitation.email ])
    end

    it "includes team name in subject" do
      expect(mail.subject).to include(team.name)
    end

    it "includes organization name in subject" do
      expect(mail.subject).to include(team.organization.name)
    end

    it "includes inviter name in subject" do
      expect(mail.subject).to include(inviter.name)
    end

    it "includes signup URL" do
      expect(mail.body.encoded).to match(/sign.*up|register/)
    end

    it "includes acceptance URL" do
      expect(mail.body.encoded).to match(/accept.*invitation/)
    end
  end
end
