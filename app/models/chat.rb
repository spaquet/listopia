# app/models/chat.rb
#
# Chat model for unified chat system
# Represents a conversation thread with messages

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
#  visibility         :string           default("private")
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  model_id           :bigint
#  organization_id    :uuid
#  team_id            :uuid
#  user_id            :uuid             not null
#
# Indexes
#
#  index_chats_on_conversation_state              (conversation_state)
#  index_chats_on_last_message_at                 (last_message_at)
#  index_chats_on_last_stable_at                  (last_stable_at)
#  index_chats_on_model_id                        (model_id)
#  index_chats_on_organization_id                 (organization_id)
#  index_chats_on_organization_id_and_created_at  (organization_id,created_at)
#  index_chats_on_organization_id_and_user_id     (organization_id,user_id)
#  index_chats_on_status                          (status)
#  index_chats_on_team_id                         (team_id)
#  index_chats_on_team_id_and_user_id             (team_id,user_id)
#  index_chats_on_user_id                         (user_id)
#  index_chats_on_user_id_and_created_at          (user_id,created_at)
#  index_chats_on_user_id_and_status              (user_id,status)
#  index_chats_on_visibility                      (visibility)
#
# Foreign Keys
#
#  fk_rails_...  (model_id => models.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (team_id => teams.id)
#  fk_rails_...  (user_id => users.id)
#
class Chat < ApplicationRecord
  belongs_to :user
  belongs_to :organization
  belongs_to :team, optional: true
  belongs_to :focused_resource, polymorphic: true, optional: true

  has_many :messages, dependent: :destroy

  store :metadata, accessors: [:rag_enabled, :model, :system_prompt], coder: JSON

  enum :status, { active: "active", archived: "archived", deleted: "deleted" }

  validates :user_id, presence: true
  validates :organization_id, presence: true
  validates :title, length: { maximum: 255 }, allow_blank: true

  scope :active, -> { where(status: :active) }
  scope :by_user, ->(user) { where(user_id: user.id) }
  scope :by_organization, ->(org) { where(organization_id: org.id) }
  scope :recent, -> { order(updated_at: :desc) }
  scope :ordered, -> { order(created_at: :asc) }
  scope :with_messages, -> { includes(:messages) }

  before_create :set_default_title

  # Get last N messages
  def recent_messages(limit = 20)
    messages.ordered.last(limit)
  end

  # Get message count
  def message_count
    messages.count
  end

  # Check if chat is empty
  def empty?
    messages.count == 0
  end

  # Get user message count
  def user_message_count
    messages.user_messages.count
  end

  # Get assistant message count
  def assistant_message_count
    messages.assistant_messages.count
  end

  # Get conversation turn count (user + assistant pairs)
  def turn_count
    (user_message_count.to_f / [assistant_message_count, 1].max).ceil
  end

  # Auto-generate title from first user message
  def generate_title_from_content
    first_user_msg = messages.user_messages.ordered.first
    return unless first_user_msg&.content.present?

    new_title = first_user_msg.content.truncate(100)
    update(title: new_title) if title.blank?
  end

  # Check if chat has context
  def has_context?
    focused_resource.present?
  end

  # Get chat context object
  def build_context(location: :dashboard)
    ChatContext.new(
      chat: self,
      user: user,
      organization: organization,
      location: location,
      focused_resource: focused_resource
    )
  end

  # Clone this chat (useful for "New Chat" based on current context)
  def clone_with_context(new_focused_resource = nil)
    Chat.create(
      user: user,
      organization: organization,
      focused_resource: new_focused_resource || focused_resource,
      metadata: metadata.dup
    )
  end

  # Archive this chat
  def archive!
    update(status: :archived)
  end

  # Restore archived chat
  def restore!
    update(status: :active)
  end

  # Soft delete
  def soft_delete!
    update(status: :deleted)
  end

  private

  def set_default_title
    self.title ||= "New Conversation"
  end
end
