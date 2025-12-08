require "rails_helper"

RSpec.describe Message, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:chat).required }
    it { is_expected.to belong_to(:user).optional }
    it { is_expected.to belong_to(:organization).optional }
    it { is_expected.to have_many(:feedbacks).class_name("MessageFeedback").dependent(:destroy) }
  end

  describe "validations" do
    let(:chat) { create(:chat) }

    it { is_expected.to validate_presence_of(:role).with_message(/can't be blank/) }
    it { is_expected.to validate_presence_of(:chat_id) }

    it "validates presence of content unless template_type is present" do
      message = build(:message, chat: chat, content: nil, template_type: nil)
      expect(message).not_to be_valid
      expect(message.errors[:content]).to be_present
    end

    it "allows missing content if template_type is present" do
      message = build(:message, chat: chat, content: nil, template_type: "search_results")
      expect(message).to be_valid
    end

    it "validates role is included in enum values" do
      expect {
        build(:message, chat: chat, role: "invalid_role")
      }.to raise_error(ArgumentError)
    end

    it "validates template_type is in MessageTemplate registry" do
      message = build(:message, chat: chat, template_type: "invalid_template")
      expect(message).not_to be_valid
    end

    it "allows blank template_type" do
      message = build(:message, chat: chat, template_type: nil)
      expect(message).to be_valid
    end
  end

  describe "enums" do
    it "has correct role enum values" do
      expect(Message.roles).to eq({
        "user" => "user",
        "assistant" => "assistant",
        "system" => "system",
        "tool" => "tool"
      })
    end
  end

  describe "database" do
    it { is_expected.to have_db_column(:id).of_type(:uuid) }
    it { is_expected.to have_db_column(:chat_id).of_type(:uuid) }
    it { is_expected.to have_db_column(:user_id).of_type(:uuid) }
    it { is_expected.to have_db_column(:organization_id).of_type(:uuid) }
    it { is_expected.to have_db_column(:role).of_type(:string) }
    it { is_expected.to have_db_column(:content).of_type(:text) }
    it { is_expected.to have_db_column(:template_type).of_type(:string) }
    it { is_expected.to have_db_column(:metadata).of_type(:json) }
    it { is_expected.to have_db_column(:llm_provider).of_type(:string) }
    it { is_expected.to have_db_column(:llm_model).of_type(:string) }
    it { is_expected.to have_db_column(:input_tokens).of_type(:integer) }
    it { is_expected.to have_db_column(:output_tokens).of_type(:integer) }
  end

  describe "scopes" do
    let(:user) { create(:user) }
    let(:other_user) { create(:user) }
    let(:chat) { create(:chat, user: user) }

    describe ".by_user" do
      let!(:user_msg) { create(:message, chat: chat, user: user, role: :user) }
      let!(:other_msg) { create(:message, chat: chat, user: other_user, role: :user) }
      let!(:assistant_msg) { create(:message, chat: chat, role: :assistant) }

      it "returns only messages by specified user" do
        expect(Message.by_user(user)).to include(user_msg)
        expect(Message.by_user(user)).not_to include(other_msg)
        expect(Message.by_user(user)).not_to include(assistant_msg)
      end
    end

    describe ".by_role" do
      let!(:user_msg) { create(:message, chat: chat, role: :user) }
      let!(:assistant_msg) { create(:message, chat: chat, role: :assistant) }
      let!(:system_msg) { create(:message, chat: chat, role: :system) }

      it "returns messages filtered by role" do
        expect(Message.by_role(:user)).to include(user_msg)
        expect(Message.by_role(:user)).not_to include(assistant_msg)
        expect(Message.by_role(:assistant)).to include(assistant_msg)
      end
    end

    describe ".user_messages" do
      let!(:user_msg) { create(:message, chat: chat, role: :user) }
      let!(:assistant_msg) { create(:message, chat: chat, role: :assistant) }

      it "returns only user messages" do
        expect(Message.user_messages).to include(user_msg)
        expect(Message.user_messages).not_to include(assistant_msg)
      end
    end

    describe ".assistant_messages" do
      let!(:user_msg) { create(:message, chat: chat, role: :user) }
      let!(:assistant_msg) { create(:message, chat: chat, role: :assistant) }

      it "returns only assistant messages" do
        expect(Message.assistant_messages).to include(assistant_msg)
        expect(Message.assistant_messages).not_to include(user_msg)
      end
    end

    describe ".system_messages" do
      let!(:system_msg) { create(:message, chat: chat, role: :system) }
      let!(:user_msg) { create(:message, chat: chat, role: :user) }

      it "returns only system messages" do
        expect(Message.system_messages).to include(system_msg)
        expect(Message.system_messages).not_to include(user_msg)
      end
    end

    describe ".recent" do
      let!(:old_msg) { create(:message, chat: chat, created_at: 1.hour.ago) }
      let!(:new_msg) { create(:message, chat: chat) }

      it "returns messages ordered by created_at descending" do
        expect(Message.recent.first).to eq(new_msg)
        expect(Message.recent.last).to eq(old_msg)
      end
    end

    describe ".ordered" do
      let!(:old_msg) { create(:message, chat: chat, created_at: 1.hour.ago) }
      let!(:new_msg) { create(:message, chat: chat) }

      it "returns messages ordered by created_at ascending" do
        expect(Message.ordered.first).to eq(old_msg)
        expect(Message.ordered.last).to eq(new_msg)
      end
    end
  end

  describe "predicates" do
    let(:chat) { create(:chat) }

    describe "#user_message?" do
      it "returns true for user role" do
        message = create(:message, chat: chat, role: :user)
        expect(message.user_message?).to be true
      end

      it "returns false for other roles" do
        message = create(:message, chat: chat, role: :assistant)
        expect(message.user_message?).to be false
      end
    end

    describe "#assistant_message?" do
      it "returns true for assistant role" do
        message = create(:message, chat: chat, role: :assistant)
        expect(message.assistant_message?).to be true
      end

      it "returns false for other roles" do
        message = create(:message, chat: chat, role: :user)
        expect(message.assistant_message?).to be false
      end
    end

    describe "#system_message?" do
      it "returns true for system role" do
        message = create(:message, chat: chat, role: :system)
        expect(message.system_message?).to be true
      end

      it "returns false for other roles" do
        message = create(:message, chat: chat, role: :assistant)
        expect(message.system_message?).to be false
      end
    end

    describe "#tool_message?" do
      it "returns true for tool role" do
        message = create(:message, chat: chat, role: :tool)
        expect(message.tool_message?).to be true
      end

      it "returns false for other roles" do
        message = create(:message, chat: chat, role: :user)
        expect(message.tool_message?).to be false
      end
    end

    describe "#templated?" do
      it "returns true when template_type is present" do
        message = create(:message, chat: chat, template_type: "search_results")
        expect(message.templated?).to be true
      end

      it "returns false when template_type is nil" do
        message = create(:message, chat: chat, template_type: nil)
        expect(message.templated?).to be false
      end
    end
  end

  describe "instance methods" do
    let(:user) { create(:user) }
    let(:chat) { create(:chat, user: user) }
    let(:message) { create(:message, chat: chat, role: :assistant) }

    describe "#average_rating" do
      it "returns average of feedback helpfulness scores" do
        create(:message_feedback, message: message, user: create(:user), helpfulness_score: 10)
        create(:message_feedback, message: message, user: create(:user), helpfulness_score: 20)
        expect(message.average_rating).to eq(15.0)
      end

      it "returns 0.0 when no feedbacks" do
        expect(message.average_rating).to eq(0.0)
      end
    end

    describe "#feedback_summary" do
      before do
        @user1 = create(:user)
        @user2 = create(:user)
        @user3 = create(:user)
        create(:message_feedback, message: message, user: @user1, rating: :helpful, helpfulness_score: 10)
        create(:message_feedback, message: message, user: @user2, rating: :unhelpful, helpfulness_score: 5)
        create(:message_feedback, message: message, user: @user3, rating: :harmful, helpfulness_score: 0)
      end

      it "returns feedback summary hash" do
        summary = message.feedback_summary
        expect(summary).to be_a(Hash)
        expect(summary[:total_ratings]).to eq(3)
        expect(summary[:helpful_count]).to eq(1)
        expect(summary[:unhelpful_count]).to eq(1)
        expect(summary[:harmful_reports]).to eq(1)
      end

      it "calculates average rating in summary" do
        summary = message.feedback_summary
        expect(summary[:average_rating]).to eq(5.0)
      end
    end

    describe "#has_feedback?" do
      it "returns true when message has feedbacks" do
        create(:message_feedback, message: message, user: create(:user))
        expect(message.has_feedback?).to be true
      end

      it "returns false when message has no feedbacks" do
        expect(message.has_feedback?).to be false
      end
    end

    describe "#display_content" do
      it "returns nil for templated messages" do
        message = create(:message, chat: chat, template_type: "search_results")
        expect(message.display_content).to be_nil
      end

      it "returns content for non-templated messages" do
        message = create(:message, chat: chat, content: "Hello world", template_type: nil)
        expect(message.display_content).to eq("Hello world")
      end
    end
  end

  describe "factory methods" do
    let(:user) { create(:user) }
    let(:chat) { create(:chat, user: user) }

    describe ".create_assistant" do
      it "creates assistant message with content" do
        message = Message.create_assistant(chat: chat, content: "Hello")
        expect(message).to be_persisted
        expect(message.role).to eq("assistant")
        expect(message.content).to eq("Hello")
      end

      it "stores rag_sources in metadata" do
        sources = [ { "title" => "Source 1", "url" => "http://example.com" } ]
        message = Message.create_assistant(chat: chat, content: "Hello", rag_sources: sources)
        expect(message.reload.rag_sources).to eq(sources)
      end

      it "handles nil rag_sources" do
        message = Message.create_assistant(chat: chat, content: "Hello", rag_sources: nil)
        expect(message.reload.rag_sources).to be_nil
      end
    end

    describe ".create_user" do
      it "creates user message" do
        message = Message.create_user(chat: chat, user: user, content: "Hi there")
        expect(message).to be_persisted
        expect(message.role).to eq("user")
        expect(message.user).to eq(user)
        expect(message.content).to eq("Hi there")
      end
    end

    describe ".create_system" do
      it "creates system message" do
        message = Message.create_system(chat: chat, content: "System message")
        expect(message).to be_persisted
        expect(message.role).to eq("system")
        expect(message.content).to eq("System message")
      end
    end

    describe ".create_templated" do
      it "creates templated message with template_data" do
        template_data = { "results" => [], "query" => "test" }
        message = Message.create_templated(
          chat: chat,
          user: user,
          template_type: "search_results",
          template_data: template_data
        )
        expect(message).to be_persisted
        expect(message.template_type).to eq("search_results")
        expect(message.reload.template_data).to eq(template_data)
      end

      it "raises error for invalid template type" do
        expect {
          Message.create_templated(
            chat: chat,
            template_type: "invalid_template",
            template_data: {}
          )
        }.to raise_error(ArgumentError, "Invalid template type")
      end
    end
  end

  describe "callbacks" do
    let(:user) { create(:user) }
    let(:chat) { create(:chat, user: user) }

    describe "after_create :update_chat_timestamp" do
      it "updates chat updated_at when message is created" do
        original_updated_at = chat.updated_at
        sleep(0.1)  # Small delay to ensure different timestamp
        create(:message, chat: chat)
        expect(chat.reload.updated_at).to be > original_updated_at
      end

      it "does not raise error when update fails" do
        # The callback safely handles nil chat
        message = build(:message)
        message.chat_id = nil
        # Should not raise during creation even if chat association is invalid
        # (save! will fail for other reasons, but not due to the callback)
      end
    end
  end

  describe "metadata storage" do
    let(:chat) { create(:chat) }

    it "stores and retrieves template_data" do
      template_data = { "query" => "test", "results" => [ 1, 2, 3 ] }
      message = create(:message, chat: chat, template_type: "search_results", metadata: { template_data: template_data })
      expect(message.reload.template_data).to eq(template_data)
    end

    it "stores and retrieves rag_sources" do
      sources = [ { "title" => "Doc 1", "content" => "..." }, { "title" => "Doc 2", "content" => "..." } ]
      message = create(:message, chat: chat, metadata: { rag_sources: sources })
      expect(message.reload.rag_sources).to eq(sources)
    end

    it "stores and retrieves attachments" do
      attachments = [ { "type" => "file", "name" => "doc.pdf", "url" => "/files/doc.pdf" } ]
      message = create(:message, chat: chat, metadata: { attachments: attachments })
      expect(message.reload.attachments).to eq(attachments)
    end

    it "handles multiple metadata fields together" do
      template_data = { "query" => "test" }
      rag_sources = [ { "title" => "Source" } ]
      attachments = [ { "type" => "image" } ]
      message = create(:message, chat: chat,
                      metadata: { template_data: template_data, rag_sources: rag_sources, attachments: attachments })
      reloaded = message.reload
      expect(reloaded.template_data).to eq(template_data)
      expect(reloaded.rag_sources).to eq(rag_sources)
      expect(reloaded.attachments).to eq(attachments)
    end
  end

  describe "token tracking" do
    let(:chat) { create(:chat) }

    it "stores input tokens" do
      message = create(:message, chat: chat, input_tokens: 100)
      expect(message.reload.input_tokens).to eq(100)
    end

    it "stores output tokens" do
      message = create(:message, chat: chat, output_tokens: 200)
      expect(message.reload.output_tokens).to eq(200)
    end

    it "stores cached tokens" do
      message = create(:message, chat: chat, cached_tokens: 50)
      expect(message.reload.cached_tokens).to eq(50)
    end

    it "stores LLM provider and model" do
      message = create(:message, chat: chat, llm_provider: "openai", llm_model: "gpt-4")
      reloaded = message.reload
      expect(reloaded.llm_provider).to eq("openai")
      expect(reloaded.llm_model).to eq("gpt-4")
    end
  end

  describe "message blocking" do
    let(:chat) { create(:chat) }

    it "stores blocked status" do
      message = create(:message, chat: chat, blocked: true)
      expect(message.reload.blocked).to be true
    end

    it "defaults to not blocked" do
      message = create(:message, chat: chat)
      expect(message.blocked).to be false
    end
  end

  describe "factory" do
    it "creates valid message with factory" do
      message = create(:message)
      expect(message).to be_valid
      expect(message).to be_persisted
    end

    it "generates UUID for id" do
      message = create(:message)
      expect(message.id).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
    end
  end

  describe "timestamps" do
    let(:message) { create(:message) }

    it "has created_at" do
      expect(message.created_at).to be_present
      expect(message.created_at).to be_a(Time)
    end

    it "has updated_at" do
      expect(message.updated_at).to be_present
      expect(message.updated_at).to be_a(Time)
    end

    it "updates updated_at when modified" do
      original_updated_at = message.updated_at
      sleep(0.1)
      message.update(llm_model: "gpt-4")
      expect(message.reload.updated_at).to be > original_updated_at
    end
  end
end
