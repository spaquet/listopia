# spec/factories/lists.rb
# == Schema Information
#
# Table name: lists
#
#  id                        :uuid             not null, primary key
#  color_theme               :string           default("blue")
#  description               :text
#  is_public                 :boolean          default(FALSE), not null
#  list_collaborations_count :integer          default(0), not null
#  list_items_count          :integer          default(0), not null
#  list_type                 :integer          default("personal"), not null
#  metadata                  :json
#  public_permission         :integer          default("public_read"), not null
#  public_slug               :string
#  status                    :integer          default("draft"), not null
#  title                     :string           not null
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  user_id                   :uuid             not null
#
# Indexes
#
#  index_lists_on_created_at                 (created_at)
#  index_lists_on_is_public                  (is_public)
#  index_lists_on_list_collaborations_count  (list_collaborations_count)
#  index_lists_on_list_items_count           (list_items_count)
#  index_lists_on_list_type                  (list_type)
#  index_lists_on_public_permission          (public_permission)
#  index_lists_on_public_slug                (public_slug) UNIQUE
#  index_lists_on_status                     (status)
#  index_lists_on_user_id                    (user_id)
#  index_lists_on_user_id_and_created_at     (user_id,created_at)
#  index_lists_on_user_id_and_status         (user_id,status)
#  index_lists_on_user_is_public             (user_id,is_public)
#  index_lists_on_user_list_type             (user_id,list_type)
#  index_lists_on_user_status                (user_id,status)
#  index_lists_on_user_status_list_type      (user_id,status,list_type)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
FactoryBot.define do
  factory :list do
    sequence(:title) { |n| "My List #{n}" }
    description { Faker::Lorem.sentence }
    status { :active }
    color_theme { 'blue' }
    is_public { false }

    association :owner, factory: :user, strategy: :build

    # Traits for different list states
    trait :draft do
      status { :draft }
    end

    trait :active do
      status { :active }
    end

    trait :completed do
      status { :completed }
    end

    trait :archived do
      status { :archived }
    end

    trait :public do
      is_public { true }
      public_slug { SecureRandom.urlsafe_base64(8) }
    end

    trait :with_items do
      after(:create) do |list|
        create_list(:list_item, 3, list: list)
      end
    end

    trait :with_completed_items do
      after(:create) do |list|
        create_list(:list_item, 2, :completed, list: list)
        create_list(:list_item, 1, list: list)
      end
    end
  end
end
