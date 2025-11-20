namespace :users do
  desc "Fix users with nil current_organization_id by setting it to their first organization"
  task fix_current_organization: :environment do
    puts "Starting to fix users with nil current_organization_id..."

    # Find users with nil current_organization_id who have at least one organization
    affected_users = User.where(current_organization_id: nil)
                         .joins(:organizations)
                         .distinct

    count = 0
    affected_users.find_each do |user|
      first_org = user.organizations.first
      if first_org
        user.update!(current_organization_id: first_org.id)
        count += 1
        puts "✓ Fixed user #{user.email} - set current_organization_id to #{first_org.name}"
      end
    end

    puts "\nSummary:"
    puts "- Fixed #{count} users"
    puts "- Total users still with nil: #{User.where(current_organization_id: nil).count}"
  end

  desc "Show users with nil current_organization_id"
  task show_org_issues: :environment do
    puts "Users with nil current_organization_id:"
    puts "-" * 60

    nil_org_users = User.where(current_organization_id: nil)

    nil_org_users.find_each do |user|
      org_count = user.organizations.count
      puts "#{user.email} (#{user.name}) - has #{org_count} organization(s)"

      if org_count > 0
        user.organizations.each { |org| puts "  └─ #{org.name}" }
      end
    end

    puts "\nTotal: #{nil_org_users.count} users"
  end
end
