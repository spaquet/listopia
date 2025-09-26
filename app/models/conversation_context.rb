# app/models/conversation_context.rb
# == Schema Information
#
# Table name: conversation_contexts
#
#  id              :uuid             not null, primary key
#  action          :string(50)       not null
#  entity_data     :jsonb            not null
#  entity_type     :string(50)       not null
#  expires_at      :datetime
#  metadata        :jsonb            not null
#  relevance_score :integer          default(100), not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  chat_id         :uuid
#  entity_id       :uuid             not null
#  user_id         :uuid             not null
#
# Indexes
#
#  idx_contexts_user_entity_time                          (user_id,entity_type,entity_id,created_at DESC)
#  idx_on_user_id_action_created_at_a6d0f1b259            (user_id,action,created_at DESC)
#  idx_on_user_id_entity_type_created_at_d22f14e09a       (user_id,entity_type,created_at DESC)
#  index_conversation_contexts_on_chat_id                 (chat_id)
#  index_conversation_contexts_on_chat_id_and_created_at  (chat_id,created_at DESC) WHERE (chat_id IS NOT NULL)
#  index_conversation_contexts_on_entity_data             (entity_data) USING gin
#  index_conversation_contexts_on_expires_at              (expires_at) WHERE (expires_at IS NOT NULL)
#  index_conversation_contexts_on_metadata                (metadata) USING gin
#  index_conversation_contexts_on_user_id                 (user_id)
#  index_conversation_contexts_on_user_id_and_created_at  (user_id,created_at DESC)
#
# Foreign Keys
#
#  fk_rails_...  (chat_id => chats.id)
#  fk_rails_...  (user_id => users.id)
#
class ConversationContext < ApplicationRecord
  belongs_to :user
  belongs_to :chat, optional: true

  # Define allowed actions - UPDATED to match what we"re actually using
  VALID_ACTIONS = %w[
    list_viewed list_created list_updated list_deleted
    list_status_changed list_visibility_changed list_duplicated
    list_share_viewed list_ai_context_requested
    item_added item_updated item_completed item_deleted item_assigned item_uncompleted
    collaboration_added collaboration_removed
    chat_started chat_switched chat_message_sent chat_error
    page_visited dashboard_viewed lists_index_viewed
  ].freeze

  # Define allowed entity types
  VALID_ENTITY_TYPES = %w[List ListItem User Chat Page].freeze

  validates :action, inclusion: { in: VALID_ACTIONS }
  validates :entity_type, inclusion: { in: VALID_ENTITY_TYPES }
  validates :entity_id, presence: true
  validates :relevance_score, numericality: { in: 1..1000 }

  # Scopes for efficient context queries
  scope :recent, -> { order(created_at: :desc) }
  scope :for_user, ->(user) { where(user: user) }
  scope :for_chat, ->(chat) { where(chat: chat) }
  scope :for_entity_type, ->(type) { where(entity_type: type) }
  scope :for_action, ->(action) { where(action: action) }
  scope :active, -> { where("expires_at IS NULL OR expires_at > ?", Time.current) }
  scope :relevant, ->(threshold = 50) { where("relevance_score >= ?", threshold) }
  scope :within_timeframe, ->(hours = 24) { where("created_at > ?", hours.hours.ago) }

  # Complex scopes for context resolution
  scope :lists_recently_viewed, -> {
    for_entity_type("List")
      .for_action([ "list_viewed", "list_created", "list_updated" ])
      .within_timeframe(2) # 2 hours for list context
  }

  scope :items_recently_interacted, -> {
    for_entity_type("ListItem")
      .for_action([ "item_added", "item_updated", "item_completed", "item_assigned" ])
      .within_timeframe(1) # 1 hour for item context
  }

  scope :current_session_contexts, -> {
    within_timeframe(0.5) # 30 minutes for current session
      .relevant(75)
  }

  # Class methods for context creation
  def self.track_action(user:, action:, entity:, chat: nil, metadata: {})
    return unless user && action && entity

    # Handle case where entity might be invalid or about to be destroyed
    begin
      # Validate entity exists and is valid
      if entity.respond_to?(:persisted?) && !entity.persisted?
        Rails.logger.warn "Attempted to track context for non-persisted entity: #{entity.class.name}"
        return nil
      end

      # For entities that might be destroyed, capture essential data first
      entity_id = entity.respond_to?(:id) ? entity.id : entity.to_s
      entity_type = entity.class.name

      # Calculate relevance score based on action type
      relevance_score = calculate_relevance_score(action, entity, metadata)

      # Set expiration based on action type
      expires_at = calculate_expiration(action)

      # Extract entity data for efficient querying (safely)
      entity_data = safely_extract_entity_data(entity)

      create!(
        user: user,
        chat: chat,
        action: action.to_s,
        entity_type: entity_type,
        entity_id: entity_id,
        entity_data: entity_data,
        metadata: metadata,
        relevance_score: relevance_score,
        expires_at: expires_at
      )
    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.warn "Failed to track conversation context: #{e.message}"
      Rails.logger.debug "Context tracking failed for: user=#{user.id}, action=#{action}, entity=#{entity.class.name}##{entity.id rescue 'unknown'}"
      nil
    rescue => e
      Rails.logger.error "Unexpected error tracking conversation context: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      nil
    end
  end

  # Instance methods
  def entity
    @entity ||= entity_type.constantize.find_by(id: entity_id)
  end

  def expired?
    expires_at.present? && expires_at < Time.current
  end

  def relevant?(threshold = 50)
    relevance_score >= threshold
  end

  def fresh?(hours = 1)
    created_at > hours.hours.ago
  end

  def to_context_hash
    {
      action: action,
      entity_type: entity_type,
      entity_id: entity_id,
      entity_data: entity_data,
      relevance_score: relevance_score,
      created_at: created_at,
      metadata: metadata
    }
  end

  private

  def self.calculate_relevance_score(action, entity, metadata)
    base_score = case action.to_s
    when "list_viewed", "item_added", "item_updated"
      100 # High relevance for current interactions
    when "list_created", "item_completed"
      150 # Very high relevance for creation/completion
    when "page_visited", "dashboard_viewed"
      50  # Medium relevance for navigation
    when "collaboration_added"
      120 # High relevance for collaboration events
    else
      75  # Default relevance
    end

    # Boost score for recent actions
    if metadata[:immediate_context]
      base_score += 50
    end

    # Boost score for entities with rich data
    if entity.respond_to?(:list_items) && entity.list_items.any?
      base_score += 25
    end

    [ base_score, 1000 ].min # Cap at 1000
  end

  def self.calculate_expiration(action)
    case action.to_s
    when "list_viewed", "page_visited"
      4.hours.from_now # Short-term context
    when "item_added", "item_updated", "item_completed"
      2.hours.from_now # Medium-term context
    when "list_created", "collaboration_added"
      24.hours.from_now # Long-term context
    else
      1.hour.from_now # Default expiration
    end
  end

  def self.extract_entity_data(entity)
    safely_extract_entity_data(entity)
  end

  def self.safely_extract_entity_data(entity)
    begin
      case entity
      when List
        # Only access attributes if the entity is still persisted
        if entity.persisted?
          # Use direct counts to avoid N+1 queries
          {
            title: entity.title,
            status: entity.status,
            items_count: entity.list_items.count,
            completed_items: entity.list_items.where(completed: true).count,
            collaborators_count: entity.collaborators.count,
            is_public: entity.is_public?,
            list_type: entity.list_type
          }
        else
          # For destroyed or non-persisted entities, use basic data only
          {
            title: entity.title,
            status: entity.status,
            is_public: entity.is_public?,
            list_type: entity.list_type
          }
        end
      when ListItem
        if entity.persisted? && entity.list.present?
          {
            title: entity.title,
            status: entity.status,
            list_id: entity.list_id,
            list_title: entity.list.title,
            priority: entity.priority,
            assigned_user_id: entity.assigned_user_id,
            position: entity.position
          }
        else
          {
            title: entity.title,
            status: entity.status,
            list_id: entity.list_id,
            priority: entity.priority,
            position: entity.position
          }
        end
      when User
        {
          name: entity.name,
          lists_count: entity.persisted? ? entity.lists.count : 0
        }
      when Chat
        {
          title: entity.title,
          status: entity.status,
          message_count: entity.persisted? ? entity.messages.count : 0
        }
      else
        # For any other entity type (like PageEntity), return basic info
        {
          identifier: entity.respond_to?(:id) ? entity.id : entity.to_s,
          type: entity.class.name
        }
      end
    rescue => e
      Rails.logger.warn "Failed to extract entity data for #{entity.class.name}: #{e.message}"
      # Return minimal data as fallback
      {
        type: entity.class.name,
        extraction_failed: true,
        error: e.message
      }
    end
  end
end
