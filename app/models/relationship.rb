# == Schema Information
#
# Table name: relationships
#
#  id                :uuid             not null, primary key
#  child_type        :string           not null
#  metadata          :json
#  parent_type       :string           not null
#  relationship_type :string           default("parent_child"), not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  child_id          :uuid             not null
#  parent_id         :uuid             not null
#
# Indexes
#
#  index_relationships_on_child             (child_type,child_id)
#  index_relationships_on_parent            (parent_type,parent_id)
#  index_relationships_on_parent_and_child  (parent_id,parent_type,child_id,child_type) UNIQUE
#
class Relationship < ApplicationRecord
  belongs_to :parent, polymorphic: true
  belongs_to :child, polymorphic: true

  enum :relationship_type, { parent_child: 0, dependency_finish_to_start: 1 }, prefix: true
end
