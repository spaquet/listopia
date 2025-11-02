# spec/support/stub_chat_model.rb
# Stub out RubyLLM model validation for Chat in tests

if Rails.env.test?
  # Override the Chat factory to avoid RubyLLM model lookups
  FactoryBot.define do
    factory :chat do
      sequence(:title) { |n| "Chat #{n}" }
      status { "active" }
      association :user

      # Bypass all callbacks and validations during creation
      to_create do |instance|
        # Skip all Rails callbacks and validations
        Chat.skip_callbacks = true
        instance.save!(validate: false)
        Chat.skip_callbacks = false
      end
    end
  end

  # Patch Chat model to skip model resolution in tests
  class Chat < ApplicationRecord
    class << self
      attr_accessor :skip_callbacks
    end

    # Override acts_as_chat to prevent model lookups
    def self.acts_as_chat
      # In test environment, do nothing
      if Rails.env.test?
        nil
      else
        super
      end
    end
  end
end
