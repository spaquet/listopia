# == Schema Information
#
# Table name: chats
#
#  id                 :uuid             not null, primary key
#  context            :json
#  conversation_state :string           default("stable")
#  last_cleanup_at    :datetime
#  last_message_at    :datetime
#  last_stable_at     :datetime
#  metadata           :json
#  model_id_string    :string
#  status             :string           default("active")
#  title              :string(255)
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  model_id           :bigint
#  user_id            :uuid             not null
#
# Indexes
#
#  index_chats_on_conversation_state      (conversation_state)
#  index_chats_on_last_message_at         (last_message_at)
#  index_chats_on_last_stable_at          (last_stable_at)
#  index_chats_on_model_id                (model_id)
#  index_chats_on_model_id_string         (model_id_string)
#  index_chats_on_user_id                 (user_id)
#  index_chats_on_user_id_and_created_at  (user_id,created_at)
#  index_chats_on_user_id_and_status      (user_id,status)
#
# Foreign Keys
#
#  fk_rails_...  (model_id => models.id)
#  fk_rails_...  (user_id => users.id)
#
FactoryBot.define do
  factory :chat do
    sequence(:title) { |n| "Chat #{n}" }
    status { "active" }
    association :user

    # In test environment, skip RubyLLM model initialization
    to_create do |instance|
      if Rails.env.test?
        # Save without triggering acts_as_chat callbacks
        instance.save(validate: false)
      else
        instance.save!
      end
    end
  end
end
