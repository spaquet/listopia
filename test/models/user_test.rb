# == Schema Information
#
# Table name: users
#
#  id                       :uuid             not null, primary key
#  avatar_url               :string
#  bio                      :text
#  email                    :string           not null
#  email_verification_token :string
#  email_verified_at        :datetime
#  locale                   :string(10)       default("en"), not null
#  name                     :string           not null
#  password_digest          :string           not null
#  provider                 :string
#  timezone                 :string(50)       default("UTC"), not null
#  uid                      :string
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#
# Indexes
#
#  index_users_on_email                     (email) UNIQUE
#  index_users_on_email_verification_token  (email_verification_token) UNIQUE
#  index_users_on_locale                    (locale)
#  index_users_on_provider_and_uid          (provider,uid) UNIQUE
#  index_users_on_timezone                  (timezone)
#
require "test_helper"

class UserTest < ActiveSupport::TestCase
  # test "the truth" do
  #   assert true
  # end
end
