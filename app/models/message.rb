# app/models/message.rb
#
# Message model for unified chat system
# Represents a single message in a chat conversation
# Supports markdown, templates, markdown, file attachments, and user feedback

# == Schema Information
#
# Table name: messages
#
#  id                    :uuid             not null, primary key
#  cache_creation_tokens :integer
#  cached_tokens         :integer
#  content               :text
#  content_raw           :json
#  context_snapshot      :json
#  input_tokens          :integer
#  llm_model             :string
#  llm_provider          :string
#  message_type          :string           default("text")
#  metadata              :json
#  model_id_string       :string
#  output_tokens         :integer
#  processing_time       :decimal(8, 3)
#  role                  :string           not null
#  template_type         :string
#  token_count           :integer
#  created_at            :datetime         not null
#  updated_at            :datetime         not null
#  chat_id               :uuid             not null
#  model_id              :bigint
#  organization_id       :uuid
#  tool_call_id          :uuid
#  user_id               :uuid
#
# Indexes
#
#  index_messages_on_chat_and_tool_call_id        (chat_id,tool_call_id) WHERE (tool_call_id IS NOT NULL)
#  index_messages_on_chat_id                      (chat_id)
#  index_messages_on_chat_id_and_created_at       (chat_id,created_at)
#  index_messages_on_llm_provider                 (llm_provider)
#  index_messages_on_llm_provider_and_llm_model   (llm_provider,llm_model)
#  index_messages_on_message_type                 (message_type)
#  index_messages_on_model_id                     (model_id)
#  index_messages_on_model_id_string              (model_id_string)
#  index_messages_on_organization_id              (organization_id)
#  index_messages_on_organization_id_and_user_id  (organization_id,user_id)
#  index_messages_on_role                         (role)
#  index_messages_on_template_type                (template_type)
#  index_messages_on_tool_call_id                 (tool_call_id)
#  index_messages_on_user_id                      (user_id)
#  index_messages_on_user_id_and_created_at       (user_id,created_at)
#
# Foreign Keys
#
#  fk_rails_...  (chat_id => chats.id)
#  fk_rails_...  (model_id => models.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (tool_call_id => tool_calls.id)
#  fk_rails_...  (user_id => users.id)
#
class Message < ApplicationRecord
  belongs_to :chat
  belongs_to :user, optional: true
  belongs_to :organization, optional: true
  has_many :feedbacks, class_name: "MessageFeedback", dependent: :destroy

  # Store template data in metadata
  store :metadata, accessors: [:template_data, :rag_sources, :attachments], coder: JSON

  enum :role, { user: "user", assistant: "assistant", system: "system", tool: "tool" }

  validates :content, presence: true, unless: -> { template_type.present? }
  validates :role, presence: true, inclusion: { in: roles.keys }
  validates :chat_id, presence: true
  validates :template_type, inclusion: { in: MessageTemplate::REGISTRY.keys }, allow_blank: true

  scope :by_user, ->(user) { where(user_id: user.id) }
  scope :by_role, ->(role) { where(role: role) }
  scope :user_messages, -> { where(role: "user") }
  scope :assistant_messages, -> { where(role: "assistant") }
  scope :system_messages, -> { where(role: "system") }
  scope :recent, -> { order(created_at: :desc) }
  scope :ordered, -> { order(created_at: :asc) }

  after_create :update_chat_timestamp

  # Predicates for message type checking
  def user_message?
    role == "user"
  end

  def assistant_message?
    role == "assistant"
  end

  def system_message?
    role == "system"
  end

  def tool_message?
    role == "tool"
  end

  # Check if message uses template rendering
  def templated?
    template_type.present?
  end

  # Get average feedback rating
  def average_rating
    feedbacks.average(:helpfulness_score).to_f.round(2)
  end

  # Get feedback summary
  def feedback_summary
    {
      total_ratings: feedbacks.count,
      average_rating: average_rating,
      helpful_count: feedbacks.where(rating: :helpful).count,
      unhelpful_count: feedbacks.where(rating: :unhelpful).count,
      harmful_reports: feedbacks.where(rating: :harmful).count
    }
  end

  # Check if message has any feedback
  def has_feedback?
    feedbacks.count > 0
  end

  # Get content for display (either template or markdown)
  def display_content
    if templated?
      # Templates are rendered in views
      nil
    else
      content
    end
  end

  # Create assistant message with markdown content
  def self.create_assistant(chat:, content:, rag_sources: nil)
    create!(
      chat: chat,
      role: :assistant,
      content: content,
      metadata: { rag_sources: rag_sources }.compact
    )
  end

  # Create user message
  def self.create_user(chat:, user:, content:)
    create!(
      chat: chat,
      user: user,
      role: :user,
      content: content
    )
  end

  # Create templated message
  def self.create_templated(chat:, user: nil, template_type:, template_data:)
    raise ArgumentError, "Invalid template type" unless MessageTemplate.exists?(template_type)

    create!(
      chat: chat,
      user: user,
      role: :assistant,
      template_type: template_type,
      metadata: { template_data: template_data }
    )
  end

  # Create system message
  def self.create_system(chat:, content:)
    create!(
      chat: chat,
      role: :system,
      content: content
    )
  end

  private

  def update_chat_timestamp
    chat.update(updated_at: Time.current) if chat
  end
end
