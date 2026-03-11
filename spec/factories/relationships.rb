# == Schema Information
#
# Table name: relationships
#
#  id                :uuid             not null, primary key
#  child_type        :string           not null
#  metadata          :json
#  parent_type       :string           not null
#  relationship_type :integer          default("parent_child"), not null
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
FactoryBot.define do
  factory :relationship do
    # Use list items as default parent/child
    association :parent, factory: :list_item
    association :child, factory: :list_item
    parent_type { 'ListItem' }
    child_type { 'ListItem' }
    relationship_type { :parent_child }
  end
end
