# app/lib/conversation_recovery_error.rb
# Custom exception for conversation recovery scenarios

class ConversationRecoveryError < StandardError
  attr_reader :new_chat

  def initialize(message, new_chat)
    super(message)
    @new_chat = new_chat
  end
end
