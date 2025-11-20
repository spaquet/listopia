# db/seeds/migrate_users_to_organizations.rb
# This script creates a personal organization for each existing user
# Run after migrations with: rails runner db/seeds/migrate_users_to_organizations.rb

puts "Starting migration of users to organizations..."

User.transaction do
  User.find_each do |user|
    # Skip if user already has organizations
    if user.organizations.any?
      puts "✓ User #{user.email} already has organizations, skipping"
      next
    end

    # Create personal organization
    org_name = "#{user.name}'s Workspace"
    personal_org = Organization.create!(
      name: org_name,
      slug: "#{user.email.split('@')[0]}-#{user.id[0...8]}",
      size: :small,
      status: :active,
      created_by_id: user.id
    )

    # Create organization membership (owner role)
    OrganizationMembership.create!(
      organization: personal_org,
      user: user,
      role: :owner,
      status: :active,
      joined_at: user.created_at
    )

    # Set current_organization_id
    user.update_column(:current_organization_id, personal_org.id)

    puts "✓ Created personal organization for #{user.email}"
  end
end

puts "Migration complete! All users now have personal organizations."
