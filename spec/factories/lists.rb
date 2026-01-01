# spec/factories/lists.rb
# == Schema Information
#
# Table name: lists
#
#  id                        :uuid             not null, primary key
#  color_theme               :string           default("blue")
#  description               :text
#  embedding                 :vector
#  embedding_generated_at    :datetime
#  is_public                 :boolean          default(FALSE), not null
#  list_collaborations_count :integer          default(0), not null
#  list_items_count          :integer          default(0), not null
#  list_type                 :integer          default("personal"), not null
#  metadata                  :json
#  public_permission         :integer          default("public_read"), not null
#  public_slug               :string
#  requires_embedding_update :boolean          default(FALSE)
#  search_document           :tsvector
#  status                    :integer          default("draft"), not null
#  title                     :string           not null
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  organization_id           :uuid
#  parent_list_id            :uuid
#  team_id                   :uuid
#  user_id                   :uuid             not null
#
# Indexes
#
#  index_lists_on_created_at                     (created_at)
#  index_lists_on_is_public                      (is_public)
#  index_lists_on_list_collaborations_count      (list_collaborations_count)
#  index_lists_on_list_items_count               (list_items_count)
#  index_lists_on_list_type                      (list_type)
#  index_lists_on_organization_id                (organization_id)
#  index_lists_on_parent_list_id                 (parent_list_id)
#  index_lists_on_parent_list_id_and_created_at  (parent_list_id,created_at)
#  index_lists_on_public_permission              (public_permission)
#  index_lists_on_public_slug                    (public_slug) UNIQUE
#  index_lists_on_search_document                (search_document) USING gin
#  index_lists_on_status                         (status)
#  index_lists_on_team_id                        (team_id)
#  index_lists_on_user_id                        (user_id)
#  index_lists_on_user_id_and_created_at         (user_id,created_at)
#  index_lists_on_user_id_and_status             (user_id,status)
#  index_lists_on_user_is_public                 (user_id,is_public)
#  index_lists_on_user_list_type                 (user_id,list_type)
#  index_lists_on_user_parent                    (user_id,parent_list_id)
#  index_lists_on_user_status                    (user_id,status)
#  index_lists_on_user_status_list_type          (user_id,status,list_type)
#
# Foreign Keys
#
#  fk_rails_...  (parent_list_id => lists.id)
#  fk_rails_...  (user_id => users.id)
#
FactoryBot.define do
  factory :list do
    owner { association :user }
    title { Faker::Lorem.sentence(word_count: 3) }
    description { Faker::Lorem.paragraph(sentence_count: 2) }
    status { :draft }
    list_type { :personal }
    public_permission { :public_read }
    is_public { false }
    color_theme { "blue" }
    metadata { {} }
    parent_list_id { nil }
    list_items_count { 0 }
    list_collaborations_count { 0 }

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
      public_slug { "#{title.parameterize}-#{SecureRandom.hex(4)}" }
    end

    trait :public_writable do
      is_public { true }
      public_permission { :public_write }
      public_slug { "#{title.parameterize}-#{SecureRandom.hex(4)}" }
    end

    trait :professional do
      list_type { :professional }
      title { Faker::Lorem.words(number: 3).join(" ").titleize }
    end

    trait :with_items do
      after(:create) do |list|
        create_list(:list_item, 3, list: list)
      end
    end

    trait :with_collaborators do
      after(:create) do |list|
        collaborator = create(:user)
        list.collaborators.create!(
          user: collaborator,
          permission: :write
        )
      end
    end

    trait :with_sub_lists do
      after(:create) do |list|
        create_list(:list, 2, parent_list: list, owner: list.owner)
      end
    end

    trait :with_board_columns do
      after(:create) do |list|
        create_list(:board_column, 3, list: list)
      end
    end
  end
end
