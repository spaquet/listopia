# == Schema Information
#
# Table name: invitations
#
#  id                     :uuid             not null, primary key
#  email                  :string
#  invitable_type         :string           not null
#  invitation_accepted_at :datetime
#  invitation_sent_at     :datetime
#  invitation_token       :string
#  permission             :integer          default("read"), not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  invitable_id           :uuid             not null
#  invited_by_id          :uuid
#  user_id                :uuid
#
# Indexes
#
#  index_invitations_on_email                (email)
#  index_invitations_on_invitable            (invitable_type,invitable_id)
#  index_invitations_on_invitable_and_email  (invitable_id,invitable_type,email) UNIQUE WHERE (email IS NOT NULL)
#  index_invitations_on_invitable_and_user   (invitable_id,invitable_type,user_id) UNIQUE WHERE (user_id IS NOT NULL)
#  index_invitations_on_invitation_token     (invitation_token) UNIQUE
#  index_invitations_on_invited_by_id        (invited_by_id)
#  index_invitations_on_user_id              (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (invited_by_id => users.id)
#  fk_rails_...  (user_id => users.id)
#
FactoryBot.define do
  factory :invitation do
  end
end
