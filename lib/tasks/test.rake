# lib/tasks/test.rake
namespace :test do
  # Define test groups for better organization and maintainability
  TEST_GROUPS = {
    models: [
      "spec/models/chat_spec.rb",
      "spec/models/comment_spec.rb",
      "spec/models/invitation_spec.rb",
      "spec/models/list_spec.rb",
      "spec/models/list_item_spec.rb",
      "spec/models/message_spec.rb",
      "spec/models/session_spec.rb",
      "spec/models/user_spec.rb"
    ],
    policies: [
      "spec/policies/comment_policy_spec.rb"
    ],
    controllers: [
      "spec/requests/comments_controller_spec.rb"
    ],
    helpers: [
      "spec/helpers/admin/users_helper_spec.rb",
      "spec/helpers/application_helper_spec.rb",
      "spec/helpers/comments_helper_spec.rb",
      "spec/helpers/dashboard_helper_spec.rb",
      "spec/helpers/item_types_helper_spec.rb",
      "spec/helpers/notifications_helper_spec.rb"
    ]
  }.freeze

  # Helper task to list all available test groups
  desc "List all available test groups"
  task :groups do
    puts "\n📋 Available Test Groups:\n\n"
    TEST_GROUPS.each do |group_name, specs|
      puts "  #{group_name.to_s.upcase}"
      puts "    Tests: #{specs.count}"
      specs.each { |spec| puts "      - #{spec}" }
      puts ""
    end
  end

  # Run individual test groups
  TEST_GROUPS.each do |group_name, specs|
    desc "Run #{group_name} tests"
    task group_name => :environment do
      specs_string = specs.join(" ")
      sh "bundle exec rspec #{specs_string}"
    end
  end

  # Run all critical tests for production readiness
  desc "Run all tests required for production readiness"
  task :production_ready do
    puts "\n🚀 Running Production Ready Tests...\n\n"

    all_specs = TEST_GROUPS.values.flatten.uniq
    specs_string = all_specs.join(" ")

    puts "Running #{all_specs.count} tests across all groups..."
    puts "Groups: #{TEST_GROUPS.keys.join(', ')}\n\n"

    sh "bundle exec rspec #{specs_string}"
  end

  # Run a specific test group with optional filters
  desc "Run tests for a specific group (usage: rake test:run_group[models] or rake test:run_group[models,user_spec])"
  task :run_group, [ :group, :filter ] => :environment do |_t, args|
    group = args[:group]&.to_sym
    filter = args[:filter]

    unless TEST_GROUPS.key?(group)
      puts "\n❌ Group '#{group}' not found."
      puts "Available groups: #{TEST_GROUPS.keys.join(', ')}\n\n"
      exit 1
    end

    specs = TEST_GROUPS[group]
    specs = specs.select { |spec| spec.include?(filter) } if filter.present?

    if specs.empty?
      puts "\n❌ No tests found for group '#{group}' with filter '#{filter}'.\n\n"
      exit 1
    end

    specs_string = specs.join(" ")
    sh "bundle exec rspec #{specs_string}"
  end

  # Run tests with verbose output and coverage report
  desc "Run production ready tests with detailed output"
  task :production_ready_verbose do
    puts "\n🚀 Running Production Ready Tests (Verbose Mode)...\n\n"

    all_specs = TEST_GROUPS.values.flatten.uniq
    specs_string = all_specs.join(" ")

    sh "bundle exec rspec #{specs_string} --format documentation --color"
  end

  # Validate that all spec files in TEST_GROUPS exist
  desc "Validate that all configured test files exist"
  task :validate do
    puts "\n🔍 Validating test file configuration...\n\n"

    missing_files = []
    total_specs = 0

    TEST_GROUPS.each do |group_name, specs|
      specs.each do |spec_file|
        total_specs += 1
        unless File.exist?(spec_file)
          missing_files << "#{group_name}: #{spec_file}"
        end
      end
    end

    if missing_files.any?
      puts "❌ Missing test files:\n\n"
      missing_files.each { |file| puts "  - #{file}" }
      puts "\n"
      exit 1
    else
      puts "✅ All #{total_specs} test files found and valid!\n\n"
    end
  end
end
