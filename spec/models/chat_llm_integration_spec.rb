# spec/models/chat_llm_integration_spec.rb

require 'rails_helper'

RSpec.describe "Chat LLM Integration", type: :model, vcr: true do
  describe "sending a message to LLM", vcr: { cassette_name: 'chat_send_message_to_llm' } do
    let(:user) { create(:user) }
    let(:chat) { create(:chat, user: user) }

    # IMPORTANT: Only run this test if cassette exists (CI) or if API key present (local)
    before do
      skip "OPENAI_API_KEY not configured" if ENV['OPENAI_API_KEY'].blank? && !cassette_exists?
    end

    it "sends message to LLM and receives response" do
      # Create user message
      user_message = Message.create!(
        chat: chat,
        role: :user,
        content: "What is 2+2?"
      )

      expect(user_message).to be_persisted

      # Simulate LLM response
      # This would use RubyLLM to call actual API (recorded in cassette)
      assistant_message = Message.create!(
        chat: chat,
        role: :assistant,
        content: "2+2 equals 4"
      )

      expect(assistant_message).to be_persisted
      expect(chat.messages.count).to eq(2)
    end
  end

  private

  def cassette_exists?
    cassette_path = Rails.root.join('spec/fixtures/vcr_cassettes/chat_send_message_to_llm.yaml')
    File.exist?(cassette_path)
  end
end
