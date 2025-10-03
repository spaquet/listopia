# db/seeds.rb - Using status enum only (no completed boolean)

# Clear existing data (optional - comment out if you want to keep existing data)
puts "🧹 Cleaning existing data..."
ListItem.destroy_all
List.destroy_all
User.destroy_all

puts "🌱 Seeding database..."

# ============================================================================
# USERS
# ============================================================================
puts "\n👥 Creating users..."

mike = User.create!(
  email: "mike@listopia.com",
  password: "password123",
  password_confirmation: "password123",
  name: "Mike Johnson",
  email_verified_at: Time.current
)
puts "✓ Created user: #{mike.email}"

emma = User.create!(
  email: "emma@listopia.com",
  password: "password123",
  password_confirmation: "password123",
  name: "Emma Wilson",
  email_verified_at: Time.current
)
puts "✓ Created user: #{emma.email}"

sarah = User.create!(
  email: "sarah@listopia.com",
  password: "password123",
  password_confirmation: "password123",
  name: "Sarah Davis",
  email_verified_at: Time.current
)
puts "✓ Created user: #{sarah.email}"

alex = User.create!(
  email: "alex@listopia.com",
  password: "password123",
  password_confirmation: "password123",
  name: "Alex Martinez",
  email_verified_at: Time.current
)
puts "✓ Created user: #{alex.email}"

# ============================================================================
# LISTS
# ============================================================================
puts "\n📝 Creating lists..."

# Mike's lists
mike_work = mike.lists.create!(
  title: "Q4 Project Planning",
  description: "Key initiatives and milestones for Q4 2025",
  list_type: "professional",
  status: "active"
)
puts "✓ Created list: #{mike_work.title}"

mike_personal = mike.lists.create!(
  title: "Home Renovation",
  description: "Tasks for kitchen and bathroom remodel",
  list_type: "personal",
  status: "active"
)
puts "✓ Created list: #{mike_personal.title}"

# Emma's lists
emma_travel = emma.lists.create!(
  title: "Europe Trip 2025",
  description: "Planning our summer vacation across Europe",
  list_type: "personal",
  status: "active",
  is_public: true
)
puts "✓ Created list: #{emma_travel.title}"

emma_blog = emma.lists.create!(
  title: "Blog Content Calendar",
  description: "Article ideas and publishing schedule",
  list_type: "professional",
  status: "active"
)
puts "✓ Created list: #{emma_blog.title}"

# Sarah's lists
sarah_fitness = sarah.lists.create!(
  title: "Fitness Goals 2025",
  description: "Training plan and health objectives",
  list_type: "personal",
  status: "active"
)
puts "✓ Created list: #{sarah_fitness.title}"

sarah_learning = sarah.lists.create!(
  title: "Learning Path: Rails 8",
  description: "Study resources and practice projects",
  list_type: "professional",
  status: "active"
)
puts "✓ Created list: #{sarah_learning.title}"

# Alex's list
alex_startup = alex.lists.create!(
  title: "Startup Launch Checklist",
  description: "Everything needed to launch our SaaS product",
  list_type: "professional",
  status: "active"
)
puts "✓ Created list: #{alex_startup.title}"

# ============================================================================
# LIST ITEMS - Using status enum (pending/in_progress/completed) ONLY
# ============================================================================
puts "\n✅ Creating list items..."

# Helper method to create items without triggering callbacks that might interfere
def create_list_item_with_position(list, item_attrs, position)
  # Skip notifications and callbacks during seeding
  item_attrs_with_position = item_attrs.merge(
    position: position,
    skip_notifications: true
  )

  item = list.list_items.new(item_attrs_with_position)
  item.save!(validate: false) # Skip validations to avoid callback issues
  item
end

# Mike's work items
mike_work_items = [
  { title: "Define Q4 OKRs", description: "Set quarterly objectives and key results", item_type: "milestone", priority: "high", status: "completed" },
  { title: "Schedule team planning sessions", description: "Book conference rooms and send invites", item_type: "task", priority: "high", status: "completed" },
  { title: "Review budget allocations", description: "Analyze Q3 spending and adjust Q4 budget", item_type: "task", priority: "medium", status: "in_progress" },
  { title: "Hire 2 senior engineers", description: "Complete interview process and make offers", item_type: "task", priority: "urgent", status: "pending", due_date: 3.weeks.from_now },
  { title: "Launch new feature beta", description: "Deploy to beta users and gather feedback", item_type: "feature", priority: "high", status: "pending", due_date: 6.weeks.from_now },
  { title: "Customer feedback analysis", description: "Review Q3 surveys and NPS scores", item_type: "task", priority: "medium", status: "pending" }
]

mike_work_items.each_with_index do |item_attrs, index|
  item = create_list_item_with_position(mike_work, item_attrs, index)

  # Set status_changed_at timestamp based on status
  if item.status_completed?
    item.update_column(:status_changed_at, rand(1..10).days.ago)
  elsif item.status_in_progress?
    item.update_column(:status_changed_at, rand(1..5).days.ago)
  end
end
puts "✓ Created #{mike_work_items.count} items for #{mike_work.title}"

# Mike's personal items
mike_personal_items = [
  { title: "Get contractor quotes", description: "Contact 3 licensed contractors", item_type: "task", priority: "high", status: "completed" },
  { title: "Select cabinet designs", description: "Visit showroom and finalize selections", item_type: "task", priority: "high", status: "completed" },
  { title: "Order appliances", description: "Purchase fridge, stove, and dishwasher", item_type: "shopping", priority: "medium", status: "in_progress" },
  { title: "Schedule demolition", description: "Book crew for first week of work", item_type: "task", priority: "medium", status: "pending", due_date: 2.weeks.from_now },
  { title: "Temporary kitchen setup", description: "Set up microwave and mini-fridge in garage", item_type: "home", priority: "low", status: "pending" }
]

mike_personal_items.each_with_index do |item_attrs, index|
  item = create_list_item_with_position(mike_personal, item_attrs, index)

  if item.status_completed?
    item.update_column(:status_changed_at, rand(1..10).days.ago)
  elsif item.status_in_progress?
    item.update_column(:status_changed_at, rand(1..5).days.ago)
  end
end
puts "✓ Created #{mike_personal_items.count} items for #{mike_personal.title}"

# Emma's travel items
emma_travel_items = [
  { title: "Book flights to Paris", description: "Search for best rates on ITA Matrix", item_type: "travel", priority: "urgent", status: "completed" },
  { title: "Reserve hotels", description: "Paris (5 nights), Rome (4 nights), Barcelona (6 nights)", item_type: "travel", priority: "high", status: "completed" },
  { title: "Apply for international driving permit", description: "Visit AAA office with documents", item_type: "task", priority: "medium", status: "in_progress" },
  { title: "Research restaurants in Paris", description: "Find authentic French bistros", item_type: "reference", priority: "low", status: "pending" },
  { title: "Book Colosseum tour", description: "Reserve skip-the-line tickets", item_type: "travel", priority: "medium", status: "pending", due_date: 4.weeks.from_now },
  { title: "Create packing list", description: "List all clothing and essentials", item_type: "note", priority: "low", status: "pending" },
  { title: "Notify bank of travel dates", description: "Call to avoid card being blocked", item_type: "finance", priority: "high", status: "pending", due_date: 1.week.from_now }
]

emma_travel_items.each_with_index do |item_attrs, index|
  item = create_list_item_with_position(emma_travel, item_attrs, index)

  if item.status_completed?
    item.update_column(:status_changed_at, rand(1..15).days.ago)
  elsif item.status_in_progress?
    item.update_column(:status_changed_at, rand(1..7).days.ago)
  end
end
puts "✓ Created #{emma_travel_items.count} items for #{emma_travel.title}"

# Emma's blog items
emma_blog_items = [
  { title: "Write: 10 Rails 8 Features You Should Know", description: "Cover Solid Queue, authentication, and more", item_type: "task", priority: "high", status: "in_progress", due_date: 5.days.from_now },
  { title: "Edit: Getting Started with Hotwire", description: "Review draft and add code examples", item_type: "task", priority: "medium", status: "pending", due_date: 1.week.from_now },
  { title: "Research: AI integration trends", description: "Find latest developments in LLM APIs", item_type: "reference", priority: "low", status: "pending" },
  { title: "Create graphics for async article", description: "Design diagrams in Figma", item_type: "task", priority: "medium", status: "pending" },
  { title: "Schedule social media posts", description: "Queue up content for next 2 weeks", item_type: "task", priority: "low", status: "pending" }
]

emma_blog_items.each_with_index do |item_attrs, index|
  item = create_list_item_with_position(emma_blog, item_attrs, index)

  if item.status_in_progress?
    item.update_column(:status_changed_at, rand(1..3).days.ago)
  end
end
puts "✓ Created #{emma_blog_items.count} items for #{emma_blog.title}"

# Sarah's fitness items
sarah_fitness_items = [
  { title: "Morning run - 5K", description: "Zone 2 pace, track heart rate", item_type: "habit", priority: "high", status: "completed" },
  { title: "Strength training - Upper body", description: "Follow program week 3 day 1", item_type: "health", priority: "high", status: "completed" },
  { title: "Meal prep for the week", description: "Prepare 5 lunches and snacks", item_type: "health", priority: "medium", status: "in_progress" },
  { title: "Schedule nutritionist appointment", description: "Book follow-up consultation", item_type: "health", priority: "medium", status: "pending", due_date: 3.days.from_now },
  { title: "Register for half marathon", description: "Sign up for April race", item_type: "task", priority: "low", status: "pending", due_date: 2.weeks.from_now },
  { title: "Buy new running shoes", description: "Visit running store for gait analysis", item_type: "shopping", priority: "medium", status: "pending" }
]

sarah_fitness_items.each_with_index do |item_attrs, index|
  item = create_list_item_with_position(sarah_fitness, item_attrs, index)

  if item.status_completed?
    item.update_column(:status_changed_at, rand(1..3).days.ago)
  elsif item.status_in_progress?
    item.update_column(:status_changed_at, 1.day.ago)
  end
end
puts "✓ Created #{sarah_fitness_items.count} items for #{sarah_fitness.title}"

# Sarah's learning items
sarah_learning_items = [
  { title: "Complete Rails 8 authentication tutorial", description: "Build auth from scratch", item_type: "learning", priority: "high", status: "completed" },
  { title: "Study Solid Queue implementation", description: "Read docs and source code", item_type: "learning", priority: "high", status: "in_progress" },
  { title: "Build sample Turbo Streams app", description: "Create real-time chat application", item_type: "task", priority: "medium", status: "in_progress", due_date: 1.week.from_now },
  { title: "Watch DHH's Rails 8 keynote", description: "Take notes on new features", item_type: "learning", priority: "medium", status: "pending" },
  { title: "Contribute to Rails open source", description: "Find good first issue and submit PR", item_type: "task", priority: "low", status: "pending" },
  { title: "Join Rails Discord community", description: "Get help and share knowledge", item_type: "social", priority: "low", status: "completed" }
]

sarah_learning_items.each_with_index do |item_attrs, index|
  item = create_list_item_with_position(sarah_learning, item_attrs, index)

  if item.status_completed?
    item.update_column(:status_changed_at, rand(1..7).days.ago)
  elsif item.status_in_progress?
    item.update_column(:status_changed_at, rand(1..4).days.ago)
  end
end
puts "✓ Created #{sarah_learning_items.count} items for #{sarah_learning.title}"

# Alex's startup items
alex_startup_items = [
  { title: "Finalize MVP feature set", description: "Lock down scope for initial launch", item_type: "decision", priority: "urgent", status: "completed" },
  { title: "Set up CI/CD pipeline", description: "Configure GitHub Actions for automated deploys", item_type: "task", priority: "high", status: "completed" },
  { title: "Design landing page", description: "Create mockups in Figma", item_type: "task", priority: "high", status: "in_progress" },
  { title: "Write product documentation", description: "Create user guides and API docs", item_type: "task", priority: "medium", status: "in_progress", due_date: 2.weeks.from_now },
  { title: "Set up payment processing", description: "Integrate Stripe for subscriptions", item_type: "feature", priority: "high", status: "pending", due_date: 10.days.from_now },
  { title: "Create demo video", description: "Record product walkthrough", item_type: "task", priority: "medium", status: "pending" },
  { title: "Launch on Product Hunt", description: "Prepare launch materials and schedule", item_type: "milestone", priority: "urgent", status: "pending", due_date: 3.weeks.from_now },
  { title: "Line up beta testers", description: "Recruit 50 users for feedback", item_type: "task", priority: "high", status: "pending", due_date: 1.week.from_now }
]

alex_startup_items.each_with_index do |item_attrs, index|
  item = create_list_item_with_position(alex_startup, item_attrs, index)

  if item.status_completed?
    item.update_column(:status_changed_at, rand(1..14).days.ago)
  elsif item.status_in_progress?
    item.update_column(:status_changed_at, rand(1..5).days.ago)
  end
end
puts "✓ Created #{alex_startup_items.count} items for #{alex_startup.title}"

# ============================================================================
# COLLABORATIONS
# ============================================================================
puts "\n🤝 Creating collaborations..."

# Emma collaborates on Mike's work list
mike_work.collaborators.create!(
  user: emma,
  permission: "write"
)
puts "✓ Added Emma as collaborator on #{mike_work.title}"

# Sarah collaborates on Mike's personal list
mike_personal.collaborators.create!(
  user: sarah,
  permission: "read"
)
puts "✓ Added Sarah as collaborator on #{mike_personal.title}"

# Mike collaborates on Emma's travel list
emma_travel.collaborators.create!(
  user: mike,
  permission: "write"
)
puts "✓ Added Mike as collaborator on #{emma_travel.title}"

# Alex collaborates on Sarah's learning list
sarah_learning.collaborators.create!(
  user: alex,
  permission: "write"
)
puts "✓ Added Alex as collaborator on #{sarah_learning.title}"

# ============================================================================
# INVITATIONS (Pending)
# ============================================================================
puts "\n📧 Creating pending invitations..."

Invitation.create!(
  invitable: alex_startup,
  email: "investor@venture.com",
  invited_by: alex,
  permission: "read"
  # invitation_token will be auto-generated by before_create callback
  # user_id is nil, making this a pending invitation
)
puts "✓ Created invitation for investor@venture.com to #{alex_startup.title}"

Invitation.create!(
  invitable: emma_blog,
  email: "editor@techblog.com",
  invited_by: emma,
  permission: "write"
  # invitation_token will be auto-generated by before_create callback
  # user_id is nil, making this a pending invitation
)
puts "✓ Created invitation for editor@techblog.com to #{emma_blog.title}"

# ============================================================================
# SUMMARY
# ============================================================================

puts "\n🎉 Seeding completed successfully!"
puts "=" * 50
puts "📊 SUMMARY:"
puts "Users created: #{User.count}"
puts "Lists created: #{List.count}"
puts "  - Professional lists: #{List.where(list_type: 'professional').count}"
puts "  - Personal lists: #{List.where(list_type: 'personal').count}"
puts "  - Public lists: #{List.where(is_public: true).count}"
puts "List items created: #{ListItem.count}"
puts "  - Completed items: #{ListItem.status_completed.count}"
puts "  - In Progress items: #{ListItem.status_in_progress.count}"
puts "  - Pending items: #{ListItem.status_pending.count}"
puts "Collaborations: #{Collaborator.count}"
puts "Pending invitations: #{Invitation.pending.count}"
puts "\n👥 USER ACCESS:"
puts "• Mike (mike@listopia.com): 2 lists + collaborator on 2 others"
puts "• Emma (emma@listopia.com): 2 lists (1 public) + 1 collaboration"
puts "• Sarah (sarah@listopia.com): 2 lists + collaborator on 1 other"
puts "• Alex (alex@listopia.com): 1 list"
puts "\n🔐 All user passwords: password123"
puts "🌐 Public list: #{emma_travel.title}"
puts "\n✨ Ready to explore Listopia with status-based tracking!"
