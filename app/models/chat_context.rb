# app/models/chat_context.rb
# Persistent conversation context that tracks planning journey and enables crash recovery
# Replaces both the shallow chat.metadata states and the old PlanningContext model
# Provides single source of truth for multi-step list creation workflows

# == Schema Information
#
# Table name: chat_contexts
#
#  id                                                                                                :uuid             not null, primary key
#  complexity_level(simple, complex)                                                                 :string
#  complexity_reasoning(Why the request was classified as simple or complex)                         :text
#  detected_intent(Detected intent: create_list, navigate_to_page, etc.)                             :string
#  error_message(Error message if status is error)                                                   :text
#  generated_items(Generated items)                                                                  :jsonb
#  hierarchical_items(Parent items, subdivisions, subdivision type for nested lists)                 :jsonb
#  is_complex(Whether request is complex and needs clarifying questions)                             :boolean          default(FALSE)
#  last_activity_at(Timestamp of last interaction; used for connection recovery)                     :datetime
#  metadata(Additional metadata and performance metrics (thinking_tokens, generation_time_ms, etc.)) :jsonb
#  missing_parameters(Parameters missing from request)                                               :string           default([]), is an Array
#  parameters(Extracted parameters from request)                                                     :jsonb
#  planning_domain(Domain: vacation, sprint, roadshow, etc.)                                         :string
#  post_creation_mode(True when showing 'keep or clear context' buttons after list creation)         :boolean          default(FALSE)
#  pre_creation_answers(User's answers to pre-creation questions)                                    :jsonb
#  pre_creation_questions(Clarifying questions for complex lists)                                    :jsonb
#  recovery_checkpoint(Last known good state snapshot for crash recovery)                            :jsonb
#  request_content(Original user request)                                                            :text
#  state(State: initial, pre_creation, resource_creation, completed)                                 :string           default("initial"), not null
#  status(Status: pending, analyzing, awaiting_user_input, processing, complete, error)              :string           default("pending"), not null
#  created_at                                                                                        :datetime         not null
#  updated_at                                                                                        :datetime         not null
#  chat_id                                                                                           :uuid             not null
#  list_created_id(ID of the created list)                                                           :uuid
#  organization_id                                                                                   :uuid             not null
#  user_id                                                                                           :uuid             not null
#
# Indexes
#
#  index_chat_contexts_on_chat_id             (chat_id) UNIQUE
#  index_chat_contexts_on_last_activity_at    (last_activity_at)
#  index_chat_contexts_on_organization_id     (organization_id)
#  index_chat_contexts_on_post_creation_mode  (post_creation_mode)
#  index_chat_contexts_on_state               (state)
#  index_chat_contexts_on_status              (status)
#  index_chat_contexts_on_user_id             (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (chat_id => chats.id)
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (user_id => users.id)
#
class ChatContext < ApplicationRecord
  # Associations
  belongs_to :user
  belongs_to :chat
  belongs_to :organization
  has_many :planning_relationships, dependent: :destroy
  has_one :created_list, class_name: "List", foreign_key: "chat_context_id", required: false

  # Validations
  validates :user_id, :chat_id, :organization_id, presence: true
  validates :chat_id, uniqueness: true
  validates :state, presence: true, inclusion: { in: %w[initial pre_creation resource_creation completed] }
  validates :status, presence: true, inclusion: { in: %w[pending analyzing awaiting_user_input processing complete error] }

  # Enums
  enum :state, {
    initial: "initial",
    pre_creation: "pre_creation",
    resource_creation: "resource_creation",
    completed: "completed"
  }

  enum :status, {
    pending: "pending",
    analyzing: "analyzing",
    awaiting_user_input: "awaiting_user_input",
    processing: "processing",
    complete: "complete",
    error: "error"
  }

  # Scopes
  scope :by_user, ->(user) { where(user_id: user.id) }
  scope :by_organization, ->(org) { where(organization_id: org.id) }
  scope :active, -> { where.not(state: :completed) }
  scope :in_post_creation_mode, -> { where(post_creation_mode: true) }
  scope :recently_created, -> { order(created_at: :desc) }

  # ===== Public Instance Methods =====

  # State check helpers
  def simple?
    complexity_level == "simple"
  end

  def complex?
    complexity_level == "complex"
  end

  def awaiting_answers?
    state == "pre_creation" && pre_creation_answers.blank?
  end

  def has_unanswered_questions?
    pre_creation_questions.present? && pre_creation_answers.blank?
  end

  def list_created?
    list_created_id.present?
  end

  # State transitions
  def mark_analyzing!
    update!(status: :analyzing)
    touch_activity!
  end

  def mark_awaiting_answers!
    transition_to(:pre_creation)
    update!(status: :awaiting_user_input)
    touch_activity!
  end

  def mark_processing!
    update!(status: :processing)
    touch_activity!
  end

  def mark_complete!
    transition_to(:completed)
    update!(status: :complete)
    touch_activity!
  end

  def mark_error!(message)
    update!(status: :error, error_message: message)
    touch_activity!
  end

  def transition_to(new_state)
    update!(state: new_state)
    touch_activity!
  end

  # Answer tracking
  def record_answers(answers_hash)
    update!(pre_creation_answers: answers_hash, state: :pre_creation)
    touch_activity!
  end

  def get_answer(question_id)
    pre_creation_answers[question_id.to_s] || pre_creation_answers[question_id.to_sym]
  end

  # Questions management
  def has_questions?
    pre_creation_questions.present? && pre_creation_questions.any?
  end

  def questions_count
    pre_creation_questions&.length || 0
  end

  def questions_answered_count
    return 0 if pre_creation_answers.blank?
    pre_creation_answers.values.count { |v| v.present? }
  end

  def all_questions_answered?
    return false if !has_questions?
    questions_answered_count == questions_count
  end

  # Parameters
  def get_parameter(key)
    parameters[key.to_s] || parameters[key.to_sym]
  end

  def add_parameters(new_params)
    merged = (parameters || {}).merge(new_params.stringify_keys)
    update!(parameters: merged)
    touch_activity!
  end

  def missing_parameter?(key)
    missing_parameters.include?(key.to_s)
  end

  # Items
  def has_generated_items?
    generated_items.present? && generated_items.any?
  end

  def has_hierarchical_items?
    hierarchical_items.present? && hierarchical_items.values.any?
  end

  def parent_items
    hierarchical_items.dig("parent_items") || []
  end

  def child_items_by_subdivision
    hierarchical_items.dig("subdivisions") || {}
  end

  def relationships_map
    hierarchical_items.dig("relationships") || []
  end

  # Relationship tracking
  def add_relationship(parent_type, child_type, relationship_type, metadata = {})
    planning_relationships.create!(
      parent_type: parent_type,
      child_type: child_type,
      relationship_type: relationship_type,
      metadata: metadata
    )
    touch_activity!
  end

  def get_relationships_for_type(type, relationship_type = nil)
    query = planning_relationships.where(parent_type: type)
    query = query.where(relationship_type: relationship_type) if relationship_type.present?
    query
  end

  # Metadata helpers
  def set_metadata(key, value)
    current_metadata = metadata || {}
    current_metadata[key] = value
    update!(metadata: current_metadata)
    touch_activity!
  end

  def get_metadata(key)
    metadata&.dig(key)
  end

  def thinking_tokens
    metadata&.dig("thinking_tokens")
  end

  def generation_time_ms
    metadata&.dig("generation_time_ms")
  end

  # Activity tracking for crash recovery
  def touch_activity!
    update_column(:last_activity_at, Time.current)
  end

  # Save checkpoint for crash recovery
  def save_recovery_checkpoint!(state_data)
    update!(recovery_checkpoint: state_data)
    touch_activity!
  end

  # Get checkpoint for recovery after disconnect
  def load_recovery_checkpoint
    recovery_checkpoint || {}
  end

  # ===== Callbacks =====

  before_validation :set_defaults

  # ===== Private Methods =====

  private

  def set_defaults
    self.state ||= "initial"
    self.status ||= "pending"
    self.parameters ||= {}
    self.metadata ||= {}
    self.pre_creation_questions ||= []
    self.pre_creation_answers ||= {}
    self.generated_items ||= []
    self.hierarchical_items ||= {}
    self.missing_parameters ||= []
    self.recovery_checkpoint ||= {}
    self.last_activity_at ||= Time.current
  end
end
