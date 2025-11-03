# spec/models/user_spec.rb
require 'rails_helper'

RSpec.describe User, type: :model do
  describe '#chats' do
    let(:user) { create(:user) }

    # Add the vcr: { cassette_name: '...' } metadata
    it 'returns chats owned by user', vcr: { cassette_name: 'chats/returns_user_chats' } do
      # Build chats without saving first
      chat1 = build(:chat, user: user, title: 'Chat 1')
      chat2 = build(:chat, user: user, title: 'Chat 2')

      # Now save them - VCR will mock the API response
      chat1.save!
      chat2.save!

      other_chat = build(:chat, user: create(:user), title: 'Other Chat')
      other_chat.save!

      # Test assertions
      expect(user.chats).to include(chat1, chat2)
      expect(user.chats).not_to include(other_chat)
      expect(user.chats.count).to eq(2)
    end

    it 'destroys chats when user is deleted', vcr: { cassette_name: 'chats/destroys_on_user_delete' } do
      chat = build(:chat, user: user, title: 'Chat to delete')
      chat.save!

      expect {
        user.destroy
      }.to change(Chat, :count).by(-1)
    end
  end
end
