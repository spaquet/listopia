# spec/factories/list_collaborations.rb
# == Schema Information
#
# Table name: list_collaborations
#
#  id                     :uuid             not null, primary key
#  email                  :string
#  invitation_accepted_at :datetime
#  invitation_sent_at     :datetime
#  invitation_token       :string
#  permission             :integer          default("read"), not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  invited_by_id          :uuid
#  list_id                :uuid             not null
#  user_id                :uuid
#
# Indexes
#
#  index_list_collaborations_on_email                   (email)
#  index_list_collaborations_on_invitation_token        (invitation_token) UNIQUE
#  index_list_collaborations_on_invited_by_id           (invited_by_id)
#  index_list_collaborations_on_list_and_email          (list_id,email) UNIQUE WHERE (email IS NOT NULL)
#  index_list_collaborations_on_list_and_user           (list_id,user_id) UNIQUE WHERE (user_id IS NOT NULL)
#  index_list_collaborations_on_list_id                 (list_id)
#  index_list_collaborations_on_permission              (permission)
#  index_list_collaborations_on_user_id                 (user_id)
#  index_list_collaborations_on_user_id_and_permission  (user_id,permission)
#
# Foreign Keys
#
#  fk_rails_...  (invited_by_id => users.id)
#  fk_rails_...  (list_id => lists.id)
#  fk_rails_...  (user_id => users.id)
#
FactoryBot.define do
  factory :list_collaboration do
    permission { :read }

    association :list, strategy: :build
    association :user, strategy: :build

    # Traits for different permissions
    trait :read_permission do
      permission { :read }
    end

    trait :collaborate_permission do
      permission { :collaborate }
    end

    # Trait for pending invitation (no user, only email)
    trait :pending do
      user { nil }
      sequence(:email) { |n| "invite#{n}@example.com" }
      invitation_token { SecureRandom.urlsafe_base64(32) }
      invitation_sent_at { Time.current }
    end

    # Trait for accepted invitation
    trait :accepted do
      invitation_accepted_at { Time.current }
    end
  end
end
