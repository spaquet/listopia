# spec/models/chat_spec.rb
require 'rails_helper'

RSpec.describe Chat, type: :model do
  # Chat model uses RubyLLM's acts_as_chat which has complex initialization
  # We test the model layer that doesn't depend on LLM resolution
  # Full integration tested with VCR cassettes

  describe 'associations' do
    it { should belong_to(:user) }
    it { should have_many(:messages).dependent(:destroy) }
  end

  describe 'validations' do
    it { should validate_presence_of(:title) }
    it { should validate_length_of(:title).is_at_most(255) }
  end

  describe 'basic constraints' do
    it 'fails without title' do
      user = create(:user)
      expect {
        Chat.create!(user: user, title: nil)
      }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it 'fails without user' do
      expect {
        Chat.create!(title: 'Chat', user: nil)
      }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end
end
