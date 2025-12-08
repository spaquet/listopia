# == Schema Information
#
# Table name: comments
#
#  id               :uuid             not null, primary key
#  commentable_type :string           not null
#  content          :text             not null
#  metadata         :json
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  commentable_id   :uuid             not null
#  user_id          :uuid             not null
#
# Indexes
#
#  index_comments_on_commentable  (commentable_type,commentable_id)
#  index_comments_on_user_id      (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class Comment < ApplicationRecord
  # Logidzy for auditing changes
  has_logidze

  # Add role support
  resourcify

  belongs_to :commentable, polymorphic: true
  belongs_to :user

  validates :content, presence: true, length: { minimum: 1, maximum: 5000 }
  validates :user_id, presence: true

  # Callbacks
  after_commit :notify_comment_created, on: :create
  after_commit :notify_mentions, on: :create

  private

  # Notify about new comment
  def notify_comment_created
    return unless user && commentable

    NotificationService.new(user)
                      .notify_item_commented(self)
  end

  # Notify mentioned users
  def notify_mentions
    return unless user && commentable

    NotificationService.new(user)
                      .notify_mentions(self)
  end
end
