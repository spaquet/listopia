# app/models/message_feedback.rb
#
# MessageFeedback model for rating system
# Users can rate assistant responses as helpful/unhelpful/harmful with optional comments

# == Schema Information
#
# Table name: message_feedbacks
#
#  id                :uuid             not null, primary key
#  comment           :text
#  feedback_type     :integer
#  helpfulness_score :integer
#  rating            :integer          not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  chat_id           :uuid             not null
#  message_id        :uuid             not null
#  user_id           :uuid             not null
#
# Indexes
#
#  index_message_feedbacks_on_chat_id                 (chat_id)
#  index_message_feedbacks_on_message_id_and_user_id  (message_id,user_id) UNIQUE
#  index_message_feedbacks_on_rating                  (rating)
#  index_message_feedbacks_on_user_id_and_created_at  (user_id,created_at)
#
# Foreign Keys
#
#  fk_rails_...  (chat_id => chats.id)
#  fk_rails_...  (message_id => messages.id)
#  fk_rails_...  (user_id => users.id)
#
class MessageFeedback < ApplicationRecord
  belongs_to :message
  belongs_to :user
  belongs_to :chat

  enum :rating, { helpful: 1, neutral: 2, unhelpful: 3, harmful: 4 }
  enum :feedback_type, { accuracy: 0, relevance: 1, clarity: 2, completeness: 3 }

  validates :rating, presence: true, inclusion: { in: ratings.keys }
  validates :user_id, presence: true
  validates :message_id, presence: true
  validates :chat_id, presence: true

  # Only one feedback per user per message
  validates :user_id, uniqueness: { scope: [:message_id], message: "can only rate a message once" }

  scope :by_user, ->(user) { where(user_id: user.id) }
  scope :by_chat, ->(chat) { where(chat_id: chat.id) }
  scope :helpful, -> { where(rating: :helpful) }
  scope :unhelpful, -> { where(rating: :unhelpful) }
  scope :harmful, -> { where(rating: :harmful) }
  scope :recent, -> { order(created_at: :desc) }

  # Implicit association validations
  validate :message_belongs_to_chat
  validate :user_is_not_message_author

  # Get rating label
  def rating_label
    case rating.to_sym
    when :helpful
      "👍 Helpful"
    when :neutral
      "👌 Neutral"
    when :unhelpful
      "👎 Unhelpful"
    when :harmful
      "⚠️ Harmful Content"
    else
      rating.humanize
    end
  end

  private

  def message_belongs_to_chat
    return unless message && chat
    errors.add(:message, "must belong to the same chat") unless message.chat_id == chat_id
  end

  def user_is_not_message_author
    return unless user && message
    errors.add(:user, "cannot rate their own message") if message.user_id == user_id
  end
end
