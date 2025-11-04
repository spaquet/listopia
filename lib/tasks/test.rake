# lib/tasks/test.rake
namespace :test do
  task :production_ready do
    sh "bundle exec rspec spec/models/user_spec.rb spec/models/invitation_spec.rb spec/models/session_spec.rb"
  end
end
