# == Schema Information
#
# Table name: users
#
#  id                       :uuid             not null, primary key
#  account_metadata         :jsonb
#  admin_notes              :text
#  avatar_url               :string
#  bio                      :text
#  deactivated_at           :datetime
#  deactivated_reason       :text
#  discarded_at             :datetime
#  email                    :string           not null
#  email_verification_token :string
#  email_verified_at        :datetime
#  invited_by_admin         :boolean          default(FALSE)
#  last_sign_in_at          :datetime
#  last_sign_in_ip          :string
#  locale                   :string(10)       default("en"), not null
#  name                     :string           not null
#  password_digest          :string           not null
#  provider                 :string
#  sign_in_count            :integer          default(0), not null
#  status                   :string           default("active"), not null
#  suspended_at             :datetime
#  suspended_reason         :text
#  timezone                 :string(50)       default("UTC"), not null
#  uid                      :string
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  suspended_by_id          :uuid
#
# Indexes
#
#  index_users_on_account_metadata          (account_metadata) USING gin
#  index_users_on_deactivated_at            (deactivated_at)
#  index_users_on_discarded_at              (discarded_at)
#  index_users_on_email                     (email) UNIQUE
#  index_users_on_email_verification_token  (email_verification_token) UNIQUE
#  index_users_on_invited_by_admin          (invited_by_admin)
#  index_users_on_last_sign_in_at           (last_sign_in_at)
#  index_users_on_locale                    (locale)
#  index_users_on_provider_and_uid          (provider,uid) UNIQUE
#  index_users_on_status                    (status)
#  index_users_on_suspended_at              (suspended_at)
#  index_users_on_timezone                  (timezone)
#
# Foreign Keys
#
#  fk_rails_...  (suspended_by_id => users.id)
#
require "test_helper"

class UserTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
