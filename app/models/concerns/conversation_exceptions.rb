# app/models/concerns/conversation_exceptions.rb
# Custom exceptions for conversation handling

class ConversationRecoveryError < StandardError
  attr_reader :new_chat

  def initialize(message, new_chat)
    super(message)
    @new_chat = new_chat
  end
end

# This can also be defined in its own file if preferred:
# app/lib/conversation_recovery_error.rb
# class ConversationRecoveryError < StandardError
#   attr_reader :new_chat
#
#   def initialize(message, new_chat)
#     super(message)
#     @new_chat = new_chat
#   end
# end
