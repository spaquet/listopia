# == Schema Information
#
# Table name: comments
#
#  id                        :uuid             not null, primary key
#  commentable_type          :string           not null
#  content                   :text             not null
#  embedding                 :vector
#  embedding_generated_at    :datetime
#  metadata                  :json
#  requires_embedding_update :boolean          default(FALSE)
#  search_document           :tsvector
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  commentable_id            :uuid             not null
#  user_id                   :uuid             not null
#
# Indexes
#
#  index_comments_on_commentable      (commentable_type,commentable_id)
#  index_comments_on_search_document  (search_document) USING gin
#  index_comments_on_user_id          (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
class Comment < ApplicationRecord
  # Embedding & Search
  include SearchableEmbeddable
  include PgSearch::Model

  # Logidzy for auditing changes
  has_logidze

  # Full-text search scope
  pg_search_scope :search_by_keyword,
    against: { content: "A" },
    using: { tsearch: { prefix: true } }

  # Add role support
  resourcify

  belongs_to :commentable, polymorphic: true
  belongs_to :user

  validates :content, presence: true, length: { minimum: 1, maximum: 5000 }
  validates :user_id, presence: true

  # Callbacks
  after_commit :notify_comment_created, on: :create
  after_commit :notify_mentions, on: :create

  def content_changed?
    super
  end

  def content_for_embedding
    content
  end

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
