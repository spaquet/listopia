# == Schema Information
#
# Table name: collaborators
#
#  id                  :uuid             not null, primary key
#  collaboratable_type :string           not null
#  granted_roles       :string           default([]), not null, is an Array
#  metadata            :jsonb            not null
#  permission          :integer          default("read"), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  collaboratable_id   :uuid             not null
#  user_id             :uuid             not null
#
# Indexes
#
#  index_collaborators_on_collaboratable           (collaboratable_type,collaboratable_id)
#  index_collaborators_on_collaboratable_and_user  (collaboratable_id,collaboratable_type,user_id) UNIQUE
#  index_collaborators_on_user_id                  (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
FactoryBot.define do
  factory :collaborator do
    association :user
    permission { :read }

    # Use a polymorphic association - provide either list or list_item
    # In tests, use: create(:collaborator, collaboratable: list)
    trait :for_list do
      association :collaboratable, factory: :list, as: :collaboratable
    end

    trait :with_write_permission do
      permission { :write }
    end
  end
end
