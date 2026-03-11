require "rails_helper"

RSpec.describe NotificationMailer, type: :mailer do
  describe "#deliver_notification" do
    let(:user) { create(:user) }
    let(:notification) { instance_double(Noticed::Notification) }

    context "when notification type responds to a mailer method" do
      before do
        allow(notification).to receive(:recipient).and_return(user)
        allow(notification).to receive(:event).and_return(double(notification_type: "item_assigned"))
      end

      it "routes to the appropriate method" do
        mailer = described_class.new
        expect(mailer).to receive(:send).with("item_assigned", notification)
        mailer.deliver_notification(notification)
      end
    end

    context "when notification type doesn't respond to a mailer method" do
      before do
        allow(notification).to receive(:recipient).and_return(user)
        allow(notification).to receive(:event).and_return(double(notification_type: "unknown_type"))
      end

      it "returns early without sending" do
        mailer = described_class.new
        expect(mailer).not_to receive(:send).with("unknown_type", notification)
        mailer.deliver_notification(notification)
      end
    end
  end

  describe "#notification_email" do
    let(:user) { create(:user) }
    let(:event) { double(title: "Test Notification") }
    let(:notification) { double(recipient: user, event: event) }
    let(:mail) { described_class.notification_email(notification).deliver_now }

    it "sends email to the recipient" do
      expect { mail }.to change { ActionMailer::Base.deliveries.count }.by(1)
    end

    it "sets the correct recipient" do
      expect(mail.to).to eq([user.email])
    end

    it "uses the event title as subject" do
      expect(mail.subject).to eq(event.title)
    end

    it "sets the correct from address" do
      expect(mail.from).to eq(["noreply@listopia.com"])
    end
  end

  describe "#item_assigned" do
    let(:user) { create(:user) }
    let(:list) { create(:list) }
    let(:assigner) { create(:user, name: "Alice") }
    let(:event) do
      double(
        actor_name: assigner.name,
        target_list: list,
        params: {
          item_title: "Complete project",
          item_title: "Complete project"
        }
      )
    end
    let(:notification) { double(recipient: user, event: event) }
    let(:mail) { described_class.item_assigned(notification).deliver_now }

    it "sends email to the assigned user" do
      expect { mail }.to change { ActionMailer::Base.deliveries.count }.by(1)
    end

    it "sets the correct recipient" do
      expect(mail.to).to eq([user.email])
    end

    it "includes assigner name in subject" do
      expect(mail.subject).to include(assigner.name)
    end

    it "includes task assignment context in subject" do
      expect(mail.subject).to include("assigned")
    end

    it "includes list URL in body" do
      expect(mail.body.encoded).to match(%r{/lists/#{list.id}})
    end

    context "when no target list" do
      let(:event) do
        double(
          actor_name: assigner.name,
          target_list: nil,
          params: { item_title: "Complete project" }
        )
      end

      it "still sends the email" do
        expect { mail }.to change { ActionMailer::Base.deliveries.count }.by(1)
      end
    end
  end

  describe "#item_commented" do
    let(:user) { create(:user) }
    let(:commenter) { create(:user, name: "Bob") }
    let(:comment_text) { "This is a detailed comment about the task progress" }
    let(:event) do
      double(
        actor_name: commenter.name,
        params: {
          commentable_title: "Task Title",
          comment_preview: comment_text
        }
      )
    end
    let(:notification) { double(recipient: user, event: event) }
    let(:mail) { described_class.item_commented(notification).deliver_now }

    it "sends email to the user" do
      expect { mail }.to change { ActionMailer::Base.deliveries.count }.by(1)
    end

    it "sets the correct recipient" do
      expect(mail.to).to eq([user.email])
    end

    it "includes commenter name in subject" do
      expect(mail.subject).to include(commenter.name)
    end

    it "includes item title in subject" do
      expect(mail.subject).to include("Task Title")
    end

    it "includes comment preview in body" do
      expect(mail.body.encoded).to include(comment_text)
    end

    context "when comment is very long" do
      let(:long_comment) { "x" * 300 }
      let(:event) do
        double(
          actor_name: commenter.name,
          params: {
            commentable_title: "Task",
            comment_preview: long_comment
          }
        )
      end

      it "truncates the comment preview to 200 characters" do
        # Truncate(200) adds "..." so we check that it's limited
        expect(mail.body.encoded).to include("x" * 100)
        expect(mail.body.encoded).not_to include("x" * 300)
      end
    end
  end

  describe "#item_completed" do
    let(:user) { create(:user) }
    let(:completer) { create(:user, name: "Charlie") }
    let(:list) { create(:list) }
    let(:event) do
      double(
        actor_name: completer.name,
        target_list: list,
        params: { item_title: "Important task" }
      )
    end
    let(:notification) { double(recipient: user, event: event) }
    let(:mail) { described_class.item_completed(notification).deliver_now }

    it "sends email to the user" do
      expect { mail }.to change { ActionMailer::Base.deliveries.count }.by(1)
    end

    it "sets the correct recipient" do
      expect(mail.to).to eq([user.email])
    end

    it "includes completer name in subject" do
      expect(mail.subject).to include(completer.name)
    end

    it "includes item title in subject" do
      expect(mail.subject).to include("Important task")
    end

    it "indicates completion in subject" do
      expect(mail.subject).to include("completed")
    end

    it "includes list URL in body" do
      expect(mail.body.encoded).to match(%r{/lists/#{list.id}})
    end
  end

  describe "#priority_changed" do
    let(:user) { create(:user) }
    let(:changer) { create(:user, name: "Diana") }
    let(:list) { create(:list) }
    let(:event) do
      double(
        actor_name: changer.name,
        target_list: list,
        params: {
          item_title: "Critical bug fix",
          new_priority: "high"
        }
      )
    end
    let(:notification) { double(recipient: user, event: event) }
    let(:mail) { described_class.priority_changed(notification).deliver_now }

    it "sends email to the user" do
      expect { mail }.to change { ActionMailer::Base.deliveries.count }.by(1)
    end

    it "sets the correct recipient" do
      expect(mail.to).to eq([user.email])
    end

    it "includes item title in subject" do
      expect(mail.subject).to include("Critical bug fix")
    end

    it "indicates priority change in subject" do
      expect(mail.subject).to include("Priority")
    end

    it "includes humanized priority in body" do
      expect(mail.body.encoded).to match(/high|High/)
    end

    it "includes list URL in body" do
      expect(mail.body.encoded).to match(%r{/lists/#{list.id}})
    end
  end

  describe "#permission_changed" do
    let(:user) { create(:user) }
    let(:changer) { create(:user, name: "Eve") }
    let(:list) { create(:list) }
    let(:event) do
      double(
        actor_name: changer.name,
        target_list: list,
        params: { new_permission: "write" }
      )
    end
    let(:notification) { double(recipient: user, event: event) }
    let(:mail) { described_class.permission_changed(notification).deliver_now }

    it "sends email to the user" do
      expect { mail }.to change { ActionMailer::Base.deliveries.count }.by(1)
    end

    it "sets the correct recipient" do
      expect(mail.to).to eq([user.email])
    end

    it "indicates permission change in subject" do
      expect(mail.subject).to include("access")
    end

    it "includes list title in subject" do
      expect(mail.subject).to include(list.title)
    end

    it "includes list URL in body" do
      expect(mail.body.encoded).to match(%r{/lists/#{list.id}})
    end
  end

  describe "#team_invited" do
    let(:user) { create(:user) }
    let(:inviter) { create(:user, name: "Frank") }
    let(:event) do
      double(
        actor_name: inviter.name,
        params: { team_name: "Engineering Team" }
      )
    end
    let(:notification) { double(recipient: user, event: event) }
    let(:mail) { described_class.team_invited(notification).deliver_now }

    it "sends email to the user" do
      expect { mail }.to change { ActionMailer::Base.deliveries.count }.by(1)
    end

    it "sets the correct recipient" do
      expect(mail.to).to eq([user.email])
    end

    it "includes inviter name in subject" do
      expect(mail.subject).to include(inviter.name)
    end

    it "includes team name in subject" do
      expect(mail.subject).to include("Engineering Team")
    end

    it "indicates team invitation in subject" do
      expect(mail.subject).to include("invited")
    end
  end

  describe "#list_archived" do
    let(:user) { create(:user) }
    let(:archiver) { create(:user, name: "Grace") }
    let(:event) do
      double(
        actor_name: archiver.name,
        params: { list_title: "Old Projects" }
      )
    end
    let(:notification) { double(recipient: user, event: event) }
    let(:mail) { described_class.list_archived(notification).deliver_now }

    it "sends email to the user" do
      expect { mail }.to change { ActionMailer::Base.deliveries.count }.by(1)
    end

    it "sets the correct recipient" do
      expect(mail.to).to eq([user.email])
    end

    it "includes list title in subject" do
      expect(mail.subject).to include("Old Projects")
    end

    it "indicates archival in subject" do
      expect(mail.subject).to include("archived")
    end
  end

  describe "#mentioned" do
    let(:user) { create(:user) }
    let(:mentioner) { create(:user, name: "Henry") }
    let(:comment_text) { "Hey @Bob, check this out!" }
    let(:event) do
      double(
        actor_name: mentioner.name,
        params: {
          commentable_title: "Design Discussion",
          comment_preview: comment_text
        }
      )
    end
    let(:notification) { double(recipient: user, event: event) }
    let(:mail) { described_class.mentioned(notification).deliver_now }

    it "sends email to the mentioned user" do
      expect { mail }.to change { ActionMailer::Base.deliveries.count }.by(1)
    end

    it "sets the correct recipient" do
      expect(mail.to).to eq([user.email])
    end

    it "includes mentioner name in subject" do
      expect(mail.subject).to include(mentioner.name)
    end

    it "indicates mention in subject" do
      expect(mail.subject).to include("mentioned")
    end

    it "includes comment preview in body" do
      expect(mail.body.encoded).to include(comment_text)
    end
  end

  describe "#digest" do
    let(:user) { create(:user) }
    let(:event) do
      double(
        params: {
          frequency: "daily",
          item_count: 5,
          comment_count: 3,
          status_count: 2,
          summary_items: []
        }
      )
    end
    let(:notification) { double(recipient: user, event: event) }
    let(:mail) { described_class.digest(notification).deliver_now }

    it "sends email to the user" do
      expect { mail }.to change { ActionMailer::Base.deliveries.count }.by(1)
    end

    it "sets the correct recipient" do
      expect(mail.to).to eq([user.email])
    end

    it "includes daily digest text for daily frequency" do
      expect(mail.subject).to include("Daily")
    end

    it "includes activity summary in subject" do
      expect(mail.subject).to include("activity")
    end

    context "with weekly frequency" do
      let(:event) do
        double(
          params: {
            frequency: "weekly",
            item_count: 15,
            comment_count: 8,
            status_count: 5,
            summary_items: []
          }
        )
      end

      it "includes weekly digest text" do
        expect(mail.subject).to include("Weekly")
      end
    end

    context "with default frequency when not specified" do
      let(:event) do
        double(
          params: {
            frequency: nil,
            item_count: 5,
            comment_count: 2,
            status_count: 1,
            summary_items: []
          }
        )
      end

      it "defaults to daily digest text" do
        expect(mail.subject).to include("Daily")
      end
    end

    it "includes activity counts in body" do
      expect(mail.body.encoded).to match(/items?|comments?|changes?|statuses?/i)
    end
  end
end
