# app/models/planning_context.rb
# Rich semantic planning context that persists across the entire planning journey
# Replaces shallow chat.metadata states with a proper model-based approach

class PlanningContext < ApplicationRecord
  # Associations
  belongs_to :user
  belongs_to :chat
  belongs_to :organization
  has_many :planning_relationships, dependent: :destroy
  has_one :created_list, class_name: "List", foreign_key: "planning_context_id", required: false

  # Validations
  validates :user_id, :chat_id, :organization_id, presence: true
  validates :chat_id, uniqueness: true
  validates :state, presence: true, inclusion: { in: %w[initial pre_creation refinement resource_creation completed] }
  validates :status, presence: true, inclusion: { in: %w[pending analyzing awaiting_user_input processing complete error] }

  # Enums
  enum :state, {
    initial: "initial",
    pre_creation: "pre_creation",
    refinement: "refinement",
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
  end

  def mark_awaiting_answers!
    transition_to(:pre_creation)
    update!(status: :awaiting_user_input)
  end

  def mark_processing!
    update!(status: :processing)
  end

  def mark_complete!
    transition_to(:completed)
    update!(status: :complete)
  end

  def mark_error!(message)
    update!(status: :error, error_message: message)
  end

  def transition_to(new_state)
    update!(state: new_state)
  end

  # Answer tracking
  def record_answers(answers_hash)
    update!(pre_creation_answers: answers_hash, state: :pre_creation)
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
  end
end
