require "rails_helper"

RSpec.describe Chat, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:user).required }
    it { is_expected.to belong_to(:organization).required }
    it { is_expected.to belong_to(:team).optional }
    it { is_expected.to have_many(:messages).dependent(:destroy) }
  end

  describe "validations" do
    it { is_expected.to validate_presence_of(:user_id) }
    it { is_expected.to validate_presence_of(:organization_id) }
    it { is_expected.to validate_length_of(:title).is_at_most(255) }
  end

  describe "enums" do
    it "has correct status enum values" do
      expect(Chat.statuses).to eq({
        "active" => "active",
        "archived" => "archived",
        "deleted" => "deleted"
      })
    end
  end

  describe "database" do
    it { is_expected.to have_db_column(:id).of_type(:uuid) }
    it { is_expected.to have_db_column(:user_id).of_type(:uuid) }
    it { is_expected.to have_db_column(:organization_id).of_type(:uuid) }
    it { is_expected.to have_db_column(:status).of_type(:string) }
    it { is_expected.to have_db_column(:title).of_type(:string) }
    it { is_expected.to have_db_column(:metadata).of_type(:json) }
  end

  describe "callbacks" do
    it "sets default title on create" do
      user = create(:user)
      org = create(:organization, creator: user)
      chat = Chat.create!(user: user, organization: org)
      expect(chat.title).to eq("New Conversation")
    end

    it "preserves custom title on create" do
      user = create(:user)
      org = create(:organization, creator: user)
      chat = Chat.create!(user: user, organization: org, title: "Custom Title")
      expect(chat.title).to eq("Custom Title")
    end
  end

  describe "scopes" do
    let!(:user) { create(:user) }
    let!(:org) { create(:organization, creator: user) }

    describe ".active" do
      let!(:active_chat) { create(:chat, user: user, organization: org, status: :active) }
      let!(:archived_chat) { create(:chat, user: user, organization: org, status: :archived) }

      it "returns only active chats" do
        expect(Chat.active).to include(active_chat)
        expect(Chat.active).not_to include(archived_chat)
      end
    end

    describe ".by_user" do
      let!(:chat1) { create(:chat, user: user, organization: org) }
      let(:other_user) { create(:user) }
      let!(:chat2) { create(:chat, user: other_user, organization: org) }

      it "returns chats for a specific user" do
        expect(Chat.by_user(user)).to include(chat1)
        expect(Chat.by_user(user)).not_to include(chat2)
      end
    end

    describe ".by_organization" do
      let(:other_org) { create(:organization, creator: user) }
      let!(:chat1) { create(:chat, user: user, organization: org) }
      let!(:chat2) { create(:chat, user: user, organization: other_org) }

      it "returns chats for a specific organization" do
        expect(Chat.by_organization(org)).to include(chat1)
        expect(Chat.by_organization(org)).not_to include(chat2)
      end
    end

    describe ".recent" do
      let!(:old_chat) { create(:chat, user: user, organization: org, created_at: 1.week.ago) }
      let!(:new_chat) { create(:chat, user: user, organization: org) }

      it "returns chats ordered by updated_at descending" do
        expect(Chat.recent.first).to eq(new_chat)
        expect(Chat.recent.last).to eq(old_chat)
      end
    end

    describe ".ordered" do
      let!(:chat1) { create(:chat, user: user, organization: org, created_at: 1.hour.ago) }
      let!(:chat2) { create(:chat, user: user, organization: org) }

      it "returns chats ordered by created_at ascending" do
        expect(Chat.ordered.first).to eq(chat1)
        expect(Chat.ordered.last).to eq(chat2)
      end
    end

    describe ".with_messages" do
      let!(:chat) { create(:chat, user: user, organization: org) }

      it "includes messages association" do
        expect(Chat.with_messages.first.association(:messages).loaded?).to be true
      end
    end
  end

  describe "instance methods" do
    let(:user) { create(:user) }
    let(:org) { create(:organization, creator: user) }
    let(:chat) { create(:chat, user: user, organization: org) }

    describe "#recent_messages" do
      before do
        @msg1 = create(:message, chat: chat, role: :user)
        @msg2 = create(:message, chat: chat, role: :assistant)
        @msg3 = create(:message, chat: chat, role: :user)
      end

      it "returns recent messages in correct order" do
        recent = chat.recent_messages(2)
        expect(recent).to eq([ @msg2, @msg3 ])
      end

      it "defaults to 20 messages" do
        create_list(:message, 25, chat: chat)
        expect(chat.recent_messages.count).to eq(20)
      end
    end

    describe "#message_count" do
      it "returns the count of messages" do
        create_list(:message, 5, chat: chat)
        expect(chat.message_count).to eq(5)
      end

      it "returns 0 when chat is empty" do
        expect(chat.message_count).to eq(0)
      end
    end

    describe "#empty?" do
      it "returns true when no messages" do
        expect(chat.empty?).to be true
      end

      it "returns false when messages exist" do
        create(:message, chat: chat)
        expect(chat.empty?).to be false
      end
    end

    describe "#user_message_count" do
      before do
        create(:message, chat: chat, role: :user)
        create(:message, chat: chat, role: :user)
        create(:message, chat: chat, role: :assistant)
      end

      it "returns count of user messages" do
        expect(chat.user_message_count).to eq(2)
      end
    end

    describe "#assistant_message_count" do
      before do
        create(:message, chat: chat, role: :user)
        create(:message, chat: chat, role: :assistant)
        create(:message, chat: chat, role: :assistant)
      end

      it "returns count of assistant messages" do
        expect(chat.assistant_message_count).to eq(2)
      end
    end

    describe "#turn_count" do
      it "returns conversation turn count" do
        create(:message, chat: chat, role: :user)
        create(:message, chat: chat, role: :assistant)
        create(:message, chat: chat, role: :user)
        expect(chat.turn_count).to eq(2)
      end

      it "handles when no assistant messages" do
        create(:message, chat: chat, role: :user)
        expect(chat.turn_count).to eq(1)
      end
    end

    describe "#generate_title_from_content" do
      it "generates title from first user message" do
        chat.update(title: "")  # Clear the default title
        create(:message, chat: chat, role: :user, content: "This is a long message that should be truncated")
        chat.generate_title_from_content
        expect(chat.reload.title).to include("This is a long message")
      end

      it "does not overwrite existing title" do
        chat.update(title: "Existing Title")
        create(:message, chat: chat, role: :user, content: "New content")
        chat.generate_title_from_content
        expect(chat.title).to eq("Existing Title")
      end

      it "does nothing without user messages" do
        chat.update(title: "")
        chat.generate_title_from_content
        expect(chat.title).to be_blank
      end
    end

    describe "#has_context?" do
      it "returns true when focused_resource is present" do
        list = create(:list, owner: user, organization: org)
        chat.update(focused_resource: list)
        expect(chat.has_context?).to be true
      end

      it "returns false when focused_resource is nil" do
        expect(chat.has_context?).to be false
      end
    end

    describe "#build_context" do
      it "returns ChatContext object" do
        context = chat.build_context
        expect(context).to be_a(ChatContext)
      end

      it "passes location to context" do
        context = chat.build_context(location: :floating)
        expect(context.location).to eq(:floating)
      end

      it "includes chat and user in context" do
        context = chat.build_context
        expect(context.chat).to eq(chat)
        expect(context.user).to eq(user)
      end
    end

    describe "#clone_with_context" do
      it "creates a new chat with same user and organization" do
        cloned = chat.clone_with_context
        expect(cloned).to be_persisted
        expect(cloned.user).to eq(chat.user)
        expect(cloned.organization).to eq(chat.organization)
      end

      it "copies metadata" do
        chat.update(metadata: { model: "gpt-4" })
        cloned = chat.clone_with_context
        expect(cloned.metadata).to eq(chat.metadata)
      end

      it "updates focused_resource if provided" do
        list = create(:list, owner: user, organization: org)
        cloned = chat.clone_with_context(list)
        expect(cloned.focused_resource).to eq(list)
      end
    end

    describe "#archive!" do
      it "changes status to archived" do
        chat.archive!
        expect(chat.reload.archived?).to be true
      end
    end

    describe "#restore!" do
      before { chat.update(status: :archived) }

      it "changes status back to active" do
        chat.restore!
        expect(chat.reload.active?).to be true
      end
    end

    describe "#soft_delete!" do
      it "changes status to deleted" do
        chat.soft_delete!
        expect(chat.reload.deleted?).to be true
      end
    end
  end

  describe "metadata storage" do
    let(:user) { create(:user) }
    let(:org) { create(:organization, creator: user) }

    it "stores and retrieves rag_enabled" do
      chat = create(:chat, user: user, organization: org, rag_enabled: true)
      expect(chat.reload.rag_enabled).to be true
    end

    it "stores and retrieves model" do
      chat = create(:chat, user: user, organization: org, model: "gpt-4")
      expect(chat.reload.model).to eq("gpt-4")
    end

    it "stores and retrieves system_prompt" do
      prompt = "You are a helpful assistant"
      chat = create(:chat, user: user, organization: org, system_prompt: prompt)
      expect(chat.reload.system_prompt).to eq(prompt)
    end
  end

  describe "polymorphic focused_resource" do
    let(:user) { create(:user) }
    let(:org) { create(:organization, creator: user) }

    it "can associate with a List" do
      list = create(:list, owner: user, organization: org)
      chat = create(:chat, user: user, organization: org, focused_resource: list)
      expect(chat.reload.focused_resource).to eq(list)
    end

    it "can associate with a ListItem" do
      list = create(:list, owner: user, organization: org)
      item = create(:list_item, list: list)
      chat = create(:chat, user: user, organization: org, focused_resource: item)
      expect(chat.reload.focused_resource).to eq(item)
    end
  end

  describe "factory" do
    it "creates valid chat" do
      chat = create(:chat)
      expect(chat).to be_valid
      expect(chat).to be_persisted
    end

    it "generates UUID for id" do
      chat = create(:chat)
      expect(chat.id).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
    end
  end

  describe "timestamps" do
    let(:chat) { create(:chat) }

    it "has created_at" do
      expect(chat.created_at).to be_present
      expect(chat.created_at).to be_a(Time)
    end

    it "has updated_at" do
      expect(chat.updated_at).to be_present
      expect(chat.updated_at).to be_a(Time)
    end

    it "updates updated_at when modified" do
      original_updated_at = chat.updated_at
      chat.update(title: "New Title")
      expect(chat.reload.updated_at).to be > original_updated_at
    end
  end
end
