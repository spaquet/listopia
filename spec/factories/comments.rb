# == Schema Information
#
# Table name: comments
#
#  id               :uuid             not null, primary key
#  commentable_type :string           not null
#  content          :text             not null
#  metadata         :json
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  commentable_id   :uuid             not null
#  user_id          :uuid             not null
#
# Indexes
#
#  index_comments_on_commentable  (commentable_type,commentable_id)
#  index_comments_on_user_id      (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
FactoryBot.define do
  factory :comment do
  end
end
