# app/models/planning_relationship.rb
# Tracks relationships between items in a planning context (parent-child, dependencies)

# == Schema Information
#
# Table name: planning_relationships
#
#  id                  :uuid             not null, primary key
#  child_type          :string           not null
#  metadata            :jsonb
#  parent_type         :string           not null
#  position            :integer          default(0)
#  relationship_type   :string           not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  planning_context_id :uuid             not null
#
# Indexes
#
#  idx_on_relationship_type_planning_context_id_12f5db6f2c     (relationship_type,planning_context_id)
#  index_planning_relationships_on_parent_type_and_child_type  (parent_type,child_type)
#  index_planning_relationships_on_planning_context_id         (planning_context_id)
#
# Foreign Keys
#
#  fk_rails_...  (planning_context_id => planning_contexts.id)
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
