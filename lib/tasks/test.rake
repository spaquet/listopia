# lib/tasks/test.rake
namespace :test do
  task :production_ready do
    sh "bundle exec rspec spec/models/chat_spec.rb spec/models/message_spec.rb spec/models/user_spec.rb spec/models/invitation_spec.rb spec/models/session_spec.rb spec/models/list_spec.rb spec/models/list_item_spec.rb"
  end
end
