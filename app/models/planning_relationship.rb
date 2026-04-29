# app/models/planning_relationship.rb
# Tracks relationships between items in a planning context (parent-child, dependencies)

# == Schema Information
#
# Table name: planning_relationships
#
#  id                                                                    :uuid             not null, primary key
#  child_type(Type of child item)                                        :string           not null
#  metadata(Additional relationship metadata)                            :jsonb
#  parent_type(Type of parent item)                                      :string           not null
#  relationship_type(Type of relationship (hierarchy, dependency, etc.)) :string           not null
#  created_at                                                            :datetime         not null
#  updated_at                                                            :datetime         not null
#  chat_context_id(Reference to the planning context)                    :uuid             not null
#
# Indexes
#
#  idx_on_chat_context_id_relationship_type_0ce2ed37ab  (chat_context_id,relationship_type)
#  index_planning_relationships_on_chat_context_id      (chat_context_id)
#
# Foreign Keys
#
#  fk_rails_...  (chat_context_id => chat_contexts.id)
#
class PlanningRelationship < ApplicationRecord
  # Associations
  belongs_to :planning_context

  # Validations
  validates :planning_context_id, presence: true
  validates :parent_type, :child_type, :relationship_type, presence: true
  validates :relationship_type, inclusion: { in: %w[subdivision dependency prerequisite related] }

  # Scopes
  scope :by_parent_type, ->(type) { where(parent_type: type) }
  scope :by_relationship_type, ->(type) { where(relationship_type: type) }
  scope :ordered, -> { order(position: :asc) }

  # Get all children of a specific parent type
  def self.children_of_type(planning_context_id, parent_type, relationship_type = nil)
    query = where(planning_context_id: planning_context_id, parent_type: parent_type)
    query = query.where(relationship_type: relationship_type) if relationship_type.present?
    query.ordered
  end

  # Get metadata field with symbol/string key compatibility
  def get_metadata(key)
    metadata&.dig(key.to_s) || metadata&.dig(key.to_sym)
  end
end
