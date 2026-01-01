# == Schema Information
#
# Table name: comments
#
#  id                        :uuid             not null, primary key
#  commentable_type          :string           not null
#  content                   :text             not null
#  embedding                 :vector
#  embedding_generated_at    :datetime
#  metadata                  :json
#  requires_embedding_update :boolean          default(FALSE)
#  search_document           :tsvector
#  created_at                :datetime         not null
#  updated_at                :datetime         not null
#  commentable_id            :uuid             not null
#  user_id                   :uuid             not null
#
# Indexes
#
#  index_comments_on_commentable      (commentable_type,commentable_id)
#  index_comments_on_search_document  (search_document) USING gin
#  index_comments_on_user_id          (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
# spec/factories/comments.rb
FactoryBot.define do
  factory :comment do
    user { association :user, :verified }
    content { Faker::Lorem.paragraph(sentence_count: 3) }
    metadata { {} }

    # Polymorphic association - defaults to List
    commentable { association :list }

    trait :on_list do
      commentable { association :list }
    end

    trait :on_list_item do
      commentable { association :list_item }
    end

    trait :short do
      content { Faker::Lorem.word }
    end

    trait :long do
      content { Faker::Lorem.paragraphs(number: 10).join("\n\n") }
    end

    trait :markdown do
      content do
        "# Header\n\n**Bold text** and *italic text*\n\n- List item 1\n- List item 2\n\n[Link](https://example.com)"
      end
    end

    trait :with_special_characters do
      content { "Comment with special chars: @#$%^&*()_+-=[]{}|;:',.<>?/~`" }
    end

    trait :with_metadata do
      metadata { { source: 'web', ip: '127.0.0.1', user_agent: 'Mozilla/5.0' } }
    end

    trait :with_edited_metadata do
      metadata do
        {
          source: 'web',
          edited_at: Time.current,
          edit_count: 1,
          edited_by: 'system'
        }
      end
    end

    trait :multiline do
      content { "Line 1\nLine 2\nLine 3\nLine 4" }
    end

    trait :max_length do
      content { 'a' * 5000 }
    end

    trait :at_max_length do
      content { 'a' * 5000 }
    end

    # Create comment at a specific time
    trait :created_yesterday do
      created_at { 1.day.ago }
      updated_at { 1.day.ago }
    end

    trait :created_today do
      created_at { Time.current }
      updated_at { Time.current }
    end

    trait :created_this_week do
      created_at { 3.days.ago }
      updated_at { 3.days.ago }
    end
  end
end
