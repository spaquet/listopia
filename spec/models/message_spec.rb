# spec/models/message_spec.rb
require 'rails_helper'

RSpec.describe Message, type: :model do
  describe 'associations' do
    it { should belong_to(:chat) }
    it { should belong_to(:user).optional }
    it { should belong_to(:model).optional }
  end

  describe 'basic constraints' do
    it 'requires a chat' do
      expect {
        Message.create!(role: 'user', content: 'Test', chat: nil)
      }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe 'database schema' do
    it 'has required columns' do
      message = Message.new
      expect(message).to respond_to(:chat_id)
      expect(message).to respond_to(:role)
      expect(message).to respond_to(:content)
    end
  end
end
