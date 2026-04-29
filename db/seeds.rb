# db/seeds.rb - Using status enum only (no completed boolean)

# Clear existing data (optional - comment out if you want to keep existing data)
puts "🧹 Cleaning existing data..."

# Disable triggers to handle self-referential foreign keys
ActiveRecord::Base.connection.execute("ALTER TABLE users DISABLE TRIGGER ALL;") if Rails.env.development?

# Delete all data safely (order matters due to foreign keys)
ListItem.destroy_all
List.destroy_all
Message.destroy_all
ModerationLog.destroy_all
Chat.destroy_all
# AI Agent cleanup (new)
AiAgentFeedback.destroy_all
AiAgentRunStep.destroy_all
AiAgentInteraction.destroy_all
AiAgentRun.destroy_all
AiAgentResource.destroy_all
AiAgentTeamMembership.destroy_all
AiAgent.destroy_all
User.destroy_all

# Re-enable foreign key checks
ActiveRecord::Base.connection.execute("ALTER TABLE users ENABLE TRIGGER ALL;") if Rails.env.development?


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
mike.add_role(:admin)
puts "✓ Created user: #{mike.email} (Admin)"

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

# Create a user outside the organization
john = User.create!(
  email: "john@example.com",
  password: "password123",
  password_confirmation: "password123",
  name: "John Smith",
  email_verified_at: Time.current
)
puts "✓ Created user: #{john.email} (not in Listopia organization)"

# Create a personal organization for John
john_org = Organization.create!(
  name: "John's Workspace",
  size: "small",
  status: "active",
  created_by_id: john.id
)

OrganizationMembership.create!(
  organization: john_org,
  user: john,
  role: :owner,
  status: :active,
  joined_at: Time.current
)

john.update!(current_organization_id: john_org.id)
puts "✓ Created personal organization for John: #{john_org.name}"

# ============================================================================
# ORGANIZATIONS
# ============================================================================
puts "\n🏢 Creating organizations..."

listopia_org = Organization.create!(
  name: "Listopia",
  size: "small",
  status: "active",
  creator: mike
)
puts "✓ Created organization: #{listopia_org.name}"

# ============================================================================
# ORGANIZATION MEMBERSHIPS
# ============================================================================
puts "\n👥 Setting up organization memberships..."

OrganizationMembership.create!(
  organization: listopia_org,
  user: mike,
  role: :owner,
  status: :active
)
mike.update!(current_organization_id: listopia_org.id)
puts "✓ Mike joined as owner (current_organization set)"

OrganizationMembership.create!(
  organization: listopia_org,
  user: emma,
  role: :member,
  status: :active
)
emma.update!(current_organization_id: listopia_org.id)
puts "✓ Emma joined as member (current_organization set)"

OrganizationMembership.create!(
  organization: listopia_org,
  user: sarah,
  role: :member,
  status: :active
)
sarah.update!(current_organization_id: listopia_org.id)
puts "✓ Sarah joined as member (current_organization set)"

OrganizationMembership.create!(
  organization: listopia_org,
  user: alex,
  role: :member,
  status: :active
)
alex.update!(current_organization_id: listopia_org.id)
puts "✓ Alex joined as member (current_organization set)"

# ============================================================================
# LISTS
# ============================================================================
puts "\n📝 Creating lists..."

# Mike's lists
mike_work = mike.lists.create!(
  title: "Q4 Project Planning",
  description: "Key initiatives and milestones for Q4 2025",
  list_type: "professional",
  status: "active",
  organization: listopia_org
)
puts "✓ Created list: #{mike_work.title}"

mike_personal = mike.lists.create!(
  title: "Home Renovation",
  description: "Tasks for kitchen and bathroom remodel",
  list_type: "personal",
  status: "active",
  organization: listopia_org
)
puts "✓ Created list: #{mike_personal.title}"

# Emma's lists
emma_travel = emma.lists.create!(
  title: "Europe Trip 2025",
  description: "Planning our summer vacation across Europe",
  list_type: "personal",
  status: "active",
  is_public: true,
  organization: listopia_org
)
puts "✓ Created list: #{emma_travel.title}"

emma_blog = emma.lists.create!(
  title: "Blog Content Calendar",
  description: "Article ideas and publishing schedule",
  list_type: "professional",
  status: "active",
  organization: listopia_org
)
puts "✓ Created list: #{emma_blog.title}"

# Sarah's lists
sarah_fitness = sarah.lists.create!(
  title: "Fitness Goals 2025",
  description: "Training plan and health objectives",
  list_type: "personal",
  status: "active",
  organization: listopia_org
)
puts "✓ Created list: #{sarah_fitness.title}"

sarah_learning = sarah.lists.create!(
  title: "Learning Path: Rails 8",
  description: "Study resources and practice projects",
  list_type: "professional",
  status: "active",
  organization: listopia_org
)
puts "✓ Created list: #{sarah_learning.title}"

# Alex's list
alex_startup = alex.lists.create!(
  title: "Startup Launch Checklist",
  description: "Everything needed to launch our SaaS product",
  list_type: "professional",
  status: "active",
  organization: listopia_org
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
# COMMENTS - For Search and RAG Testing
# ============================================================================
puts "\n💬 Creating comments..."

# Comments on Mike's Q4 Planning list
comment1 = Comment.create!(
  commentable: mike_work,
  user: emma,
  content: "We should prioritize the hiring effort - critical for Q4 timeline. Strong technical candidates are in high demand right now."
)
puts "✓ Created comment on #{mike_work.title}"

comment2 = Comment.create!(
  commentable: mike_work,
  user: sarah,
  content: "Great plan! I think we should also consider updating our tech stack to Rails 8. The new features would help us move faster on development."
)
puts "✓ Created comment on #{mike_work.title}"

comment3 = Comment.create!(
  commentable: mike_work,
  user: alex,
  content: "The feature beta launch timing looks good. We should ensure all infrastructure and monitoring are ready before beta to catch issues early."
)
puts "✓ Created comment on #{mike_work.title}"

# Comments on Emma's Travel list
comment4 = Comment.create!(
  commentable: emma_travel,
  user: mike,
  content: "The Paris itinerary looks amazing! Don't miss the Louvre Museum and try some authentic French cuisine. Book restaurants in advance."
)
puts "✓ Created comment on #{emma_travel.title}"

comment5 = Comment.create!(
  commentable: emma_travel,
  user: sarah,
  content: "Europe trip is the best! Pro tip: Get a local SIM card when you arrive. Much cheaper than roaming and you'll have reliable data."
)
puts "✓ Created comment on #{emma_travel.title}"

comment6 = Comment.create!(
  commentable: emma_travel,
  user: alex,
  content: "Make sure your international driving permit is valid for Italy and Spain too. Also check rental car insurance requirements."
)
puts "✓ Created comment on #{emma_travel.title}"

# Comments on Emma's Blog list
comment7 = Comment.create!(
  commentable: emma_blog,
  user: sarah,
  content: "The Rails 8 article is highly relevant. Everyone wants to know about the new authentication system and Solid Queue features."
)
puts "✓ Created comment on #{emma_blog.title}"

comment8 = Comment.create!(
  commentable: emma_blog,
  user: alex,
  content: "Great idea to cover AI integration trends. Include information about LLM APIs, embeddings, and vector databases in your research."
)
puts "✓ Created comment on #{emma_blog.title}"

# Comments on Sarah's Learning list
comment9 = Comment.create!(
  commentable: sarah_learning,
  user: mike,
  content: "Rails 8 is fantastic. The authentication improvements and Solid ecosystem are game changers. Your learning path is well structured."
)
puts "✓ Created comment on #{sarah_learning.title}"

comment10 = Comment.create!(
  commentable: sarah_learning,
  user: emma,
  content: "Have you looked at Turbo Streams for real-time features? It's incredibly powerful for building interactive applications without JavaScript."
)
puts "✓ Created comment on #{sarah_learning.title}"

# Comments on specific list items
comment11 = Comment.create!(
  commentable: mike_work.list_items.find { |item| item.title == "Define Q4 OKRs" },
  user: sarah,
  content: "The OKRs look ambitious but achievable. Engineering capacity might be tight with the hiring effort. Let's discuss in planning."
)
puts "✓ Created comment on list item"

comment12 = Comment.create!(
  commentable: alex_startup.list_items.find { |item| item.title == "Set up payment processing" },
  user: emma,
  content: "Stripe is excellent for SaaS. Make sure to test webhook integrations and handle subscription lifecycle events properly."
)
puts "✓ Created comment on list item"

comment13 = Comment.create!(
  commentable: sarah_fitness.list_items.find { |item| item.title == "Schedule nutritionist appointment" },
  user: mike,
  content: "Great move on the nutrition focus. A professional can help you optimize your diet for endurance training and recovery."
)
puts "✓ Created comment on list item"

# Comments on Alex's startup
comment14 = Comment.create!(
  commentable: alex_startup,
  user: mike,
  content: "The startup launch checklist is comprehensive. Have you considered implementing search and RAG features for your product? It's a game changer."
)
puts "✓ Created comment on #{alex_startup.title}"

comment15 = Comment.create!(
  commentable: alex_startup,
  user: emma,
  content: "The CI/CD setup is critical. Automated testing and deployments will save you tons of time during the launch phase and beyond."
)
puts "✓ Created comment on #{alex_startup.title}"

# ============================================================================
# CHATS - For RAG Testing
# ============================================================================
puts "\n🤖 Creating chats for RAG testing..."

# Create a chat for Mike
mike_chat = Chat.create!(
  user_id: mike.id,
  title: "Work Planning Assistant",
  organization_id: listopia_org.id,
  status: "active",
  metadata: { rag_enabled: true }
)
puts "✓ Created chat for Mike with RAG enabled"

# Create messages in Mike's chat
msg1 = mike_chat.messages.create!(
  role: "user",
  content: "What are my key Q4 priorities?",
  user_id: mike.id
)

msg2 = mike_chat.messages.create!(
  role: "assistant",
  content: "Based on your lists and comments, your key Q4 priorities are:\n1. Define Q4 OKRs and objectives\n2. Schedule team planning sessions\n3. Hire 2 senior engineers\n4. Launch new feature beta\n5. Review budget allocations",
  user_id: nil,
  metadata: { rag_sources: [] }
)
puts "✓ Created messages in Mike's chat"

# Create a chat for Emma
emma_chat = Chat.create!(
  user_id: emma.id,
  title: "Travel & Content Planning",
  organization_id: listopia_org.id,
  status: "active",
  metadata: { rag_enabled: true }
)
puts "✓ Created chat for Emma with RAG enabled"

msg3 = emma_chat.messages.create!(
  role: "user",
  content: "Give me a summary of my Europe trip planning",
  user_id: emma.id
)

msg4 = emma_chat.messages.create!(
  role: "assistant",
  content: "Your Europe trip 2025 is well planned! You have flights and hotels booked for Paris (5 nights), Rome (4 nights), and Barcelona (6 nights). Upcoming tasks include applying for an international driving permit, booking a Colosseum tour, and creating a packing list.",
  user_id: nil,
  metadata: { rag_sources: [] }
)
puts "✓ Created messages in Emma's chat"

# Create a chat for Sarah
sarah_chat = Chat.create!(
  user_id: sarah.id,
  title: "Learning & Fitness Coach",
  organization_id: listopia_org.id,
  status: "active",
  metadata: { rag_enabled: true }
)
puts "✓ Created chat for Sarah with RAG enabled"

msg5 = sarah_chat.messages.create!(
  role: "user",
  content: "What should I focus on this week?",
  user_id: sarah.id
)

msg6 = sarah_chat.messages.create!(
  role: "assistant",
  content: "This week you should focus on: 1) Completing your Rails 8 authentication learning module, 2) Meal prepping for the week, 3) Continuing your Solid Queue study, and 4) Your morning runs and strength training.",
  user_id: nil,
  metadata: { rag_sources: [] }
)
puts "✓ Created messages in Sarah's chat"

# Create a chat for Alex
alex_chat = Chat.create!(
  user_id: alex.id,
  title: "Startup Launch Planning",
  organization_id: listopia_org.id,
  status: "active",
  metadata: { rag_enabled: true }
)
puts "✓ Created chat for Alex with RAG enabled"

msg7 = alex_chat.messages.create!(
  role: "user",
  content: "What's blocking our launch?",
  user_id: alex.id
)

msg8 = alex_chat.messages.create!(
  role: "assistant",
  content: "Based on your startup checklist, the critical blocking items are: 1) Design landing page (in progress), 2) Set up payment processing (Stripe integration - due in 10 days), 3) Write product documentation, 4) Line up beta testers. Once these are complete, you can proceed with the Product Hunt launch.",
  user_id: nil,
  metadata: { rag_sources: [] }
)
puts "✓ Created messages in Alex's chat"

# ============================================================================
# SUMMARY
# ============================================================================

puts "\n🎉 Seeding completed successfully!"
puts "=" * 50
puts "📊 SUMMARY:"
puts "Users created: #{User.count}"
puts "Organizations created: #{Organization.count}"
puts "Organization memberships: #{OrganizationMembership.count}"
puts "Lists created: #{List.count}"
puts "  - Professional lists: #{List.where(list_type: 'professional').count}"
puts "  - Personal lists: #{List.where(list_type: 'personal').count}"
puts "  - Public lists: #{List.where(is_public: true).count}"
puts "  - Organization-scoped lists: #{List.where.not(organization_id: nil).count}"
puts "List items created: #{ListItem.count}"
puts "  - Completed items: #{ListItem.status_completed.count}"
puts "  - In Progress items: #{ListItem.status_in_progress.count}"
puts "  - Pending items: #{ListItem.status_pending.count}"
puts "Collaborations: #{Collaborator.count}"
puts "Pending invitations: #{Invitation.pending.count}"
puts "\n💬 SEARCH & RAG DATA:"
puts "Comments created: #{Comment.count}"
puts "Chats created: #{Chat.count}"
puts "Chat messages created: #{Message.count}"
puts "  - Chats with RAG enabled: #{Chat.where("metadata->>'rag_enabled' = 'true'").count}"
puts "\n🏢 ORGANIZATIONS:"
puts "\n📍 Listopia (Shared Organization)"
puts "👥 MEMBERS:"
puts "• Mike (mike@listopia.com): ADMIN & Owner - 2 lists + collaborator on 2 others"
puts "  └─ current_organization_id: #{mike.current_organization_id} ✓"
puts "• Emma (emma@listopia.com): Member - 2 lists (1 public) + 1 collaboration"
puts "  └─ current_organization_id: #{emma.current_organization_id} ✓"
puts "• Sarah (sarah@listopia.com): Member - 2 lists + collaborator on 1 other"
puts "  └─ current_organization_id: #{sarah.current_organization_id} ✓"
puts "• Alex (alex@listopia.com): Member - 1 list"
puts "  └─ current_organization_id: #{alex.current_organization_id} ✓"
puts "\n📍 John's Workspace (Personal Organization)"
puts "👤 OWNER:"
puts "• John (john@example.com): Owner - separate organization for cross-org testing"
puts "  └─ current_organization_id: #{john.current_organization_id} ✓"
puts "\n🔐 All user passwords: password123"
puts "🌐 Public list: #{emma_travel.title}"
puts "\n💡 SEARCH & RAG TESTING:"
puts "✨ All lists and items have rich content for semantic search"
puts "✨ Comments provide discussion context for RAG to pull from"
puts "✨ Chats demonstrate RAG in action with message examples"
puts "✨ Try searching for: 'Rails 8', 'hiring', 'payment', 'travel', 'authentication'"
puts "✨ RAG will pull relevant lists, items, and comments as context"
puts "\n✅ All users have current_organization_id properly set!"
puts "✨ Ready to explore Listopia with organization-scoped access control!"
puts "\n🚀 NEXT STEPS:"
puts "1. Run migrations: bundle exec rails db:migrate (if not already done)"
puts "2. Start server: bin/dev"
puts "3. Log in as any user (password: password123)"
puts "4. Try the search feature at /search"
puts "5. Send a message in chat to see RAG in action with source attribution"

# ============================================================================
# AI AGENTS (System Agents - Redesigned with new architecture)
# ============================================================================
puts "\n🤖 Creating AI Agents..."

# 1. Task Breakdown Agent
agent_task_breakdown = AiAgent.create!(
  scope: :system_agent,
  name: "Task Breakdown Agent",
  slug: "task-breakdown",
  description: "Breaks down complex goals into actionable tasks with priorities and estimates",
  prompt: "You are a senior project manager expert at decomposing complex goals into clear, achievable tasks. Your role is to understand the user's goal, identify major phases, create specific tasks, assign realistic priorities and time estimates, and confirm the plan with the user.",
  instructions: "1. Understand the goal: Ask clarifying questions if needed\n2. Identify major phases and milestones\n3. Break into specific, actionable tasks\n4. Assign priority (low/medium/high/urgent) and effort estimate to each\n5. Ask the user to confirm or adjust before creating items",
  body_context_config: { "load" => "invocable" },
  pre_run_questions: [
    { "key" => "goal", "question" => "What is the main goal you want to accomplish?", "required" => true },
    { "key" => "deadline", "question" => "Do you have a deadline? (optional)", "required" => false }
  ],
  trigger_config: { "type" => "manual" },
  status: :active,
  model: "gpt-4o-mini",
  max_tokens_per_run: 6000,
  max_tokens_per_day: 100_000,
  max_tokens_per_month: 500_000
)
agent_task_breakdown.ai_agent_resources.create!(resource_type: "list", permission: :read_write, description: "Read and create tasks")
agent_task_breakdown.ai_agent_resources.create!(resource_type: "list_item", permission: :read_write, description: "Create and update task items")
agent_task_breakdown.tag_list.add("breakdown", "planning", "decomposition")
agent_task_breakdown.save!
puts "✓ Created agent: Task Breakdown Agent"

# 2. Status Report Agent
agent_status_report = AiAgent.create!(
  scope: :system_agent,
  name: "Status Report Agent",
  slug: "status-report",
  description: "Generates comprehensive status reports across all lists and identifies blockers",
  prompt: "You are an executive assistant skilled at synthesizing work status. Your role is to analyze all lists, count progress, identify blockers, and create clear, executive-friendly status summaries.",
  instructions: "1. Load all lists in the organization\n2. For each list: count total items, completed items, overdue items, and blocked items\n3. Identify critical blockers or at-risk deliverables\n4. Generate a formatted status report with: overall progress, at-risk items, blocked items, and action items",
  body_context_config: { "load" => "all_lists" },
  pre_run_questions: [],
  trigger_config: { "type" => "schedule", "cron" => "0 9 * * 1" },  # Monday 9am
  status: :active,
  model: "gpt-4o-mini",
  max_tokens_per_run: 5000,
  max_tokens_per_day: 80_000,
  max_tokens_per_month: 400_000
)
agent_status_report.ai_agent_resources.create!(resource_type: "list", permission: :read_only, description: "Read all lists")
agent_status_report.ai_agent_resources.create!(resource_type: "list_item", permission: :read_only, description: "Read all items")
agent_status_report.tag_list.add("reporting", "status", "summary")
agent_status_report.save!
puts "✓ Created agent: Status Report Agent"

# 3. List Organizer Agent
agent_list_organizer = AiAgent.create!(
  scope: :system_agent,
  name: "List Organizer Agent",
  slug: "list-organizer",
  description: "Optimizes list structure by detecting duplicates, suggesting reorganization, and applying changes after user approval",
  prompt: "You are a Getting Things Done (GTD) expert who helps users organize their lists for maximum clarity and actionability. You identify duplicates, suggest better prioritization, and group related items logically.",
  instructions: "1. Load the target list and all items\n2. Scan for potential duplicates or similar items (ask user if unsure)\n3. Analyze priority distribution and suggest rebalancing\n4. Suggest grouping or categorization improvements\n5. Ask user to confirm changes before applying\n6. Update items according to user feedback",
  body_context_config: { "load" => "invocable" },
  pre_run_questions: [],
  trigger_config: { "type" => "event", "event_type" => "list_item.completed" },
  status: :active,
  model: "gpt-4o-mini",
  max_tokens_per_run: 6000,
  max_tokens_per_day: 90_000,
  max_tokens_per_month: 450_000
)
agent_list_organizer.ai_agent_resources.create!(resource_type: "list", permission: :read_write, description: "Read and update list")
agent_list_organizer.ai_agent_resources.create!(resource_type: "list_item", permission: :read_write, description: "Read and update items")
agent_list_organizer.tag_list.add("organization", "gtd", "optimization")
agent_list_organizer.save!
puts "✓ Created agent: List Organizer Agent"

# 4. Research Agent
agent_research = AiAgent.create!(
  scope: :system_agent,
  name: "Research Agent",
  slug: "research-agent",
  description: "Enriches list items with relevant research findings and external information",
  prompt: "You are a thorough researcher who finds and synthesizes relevant information. Your role is to enhance list items with context, links, and useful details from web search.",
  instructions: "1. Load the target list and items\n2. For each item, search for relevant information based on the depth setting\n3. Add descriptions, links, and key findings to items\n4. Provide a summary of research results\n5. Flag any items where no relevant information was found",
  body_context_config: { "load" => "invocable" },
  pre_run_questions: [
    { "key" => "depth", "question" => "How deep should research be?", "options" => [ "quick overview", "detailed research" ], "required" => true }
  ],
  trigger_config: { "type" => "manual" },
  status: :active,
  model: "gpt-4o-mini",
  max_tokens_per_run: 8000,
  max_tokens_per_day: 120_000,
  max_tokens_per_month: 600_000
)
agent_research.ai_agent_resources.create!(resource_type: "list", permission: :read_write, description: "Read and update list")
agent_research.ai_agent_resources.create!(resource_type: "list_item", permission: :read_write, description: "Read and update items with research")
agent_research.ai_agent_resources.create!(resource_type: "web_search", permission: :expect_response, description: "Search the web for information")
agent_research.tag_list.add("research", "web-search", "enrichment")
agent_research.save!
puts "✓ Created agent: Research Agent"

# 5. List Creator Agent (for Phase 3 chat integration)
agent_list_creator = AiAgent.find_or_initialize_by(slug: "list-creator", scope: :system_agent)
agent_list_creator.assign_attributes(
  name: "List Creator Agent",
  description: "Creates lists with specific items from natural language requests via chat",
  prompt: "You are a skilled list curator. You create focused, relevant lists for users.",
  instructions: <<~INSTRUCTIONS,
    1. Read the user's full request (it may include original request + clarifying answers).
    2. Identify: list title, category (personal/professional), and what items are needed.
    3. Generate 8-15 specific, relevant, actionable items for the list.
    4. Call create_list with title, category, description (optional), and the items array.
    5. Do NOT call ask_user — all context is already provided in the input.
  INSTRUCTIONS
  body_context_config: { "load" => "none" },
  pre_run_questions: [],
  trigger_config: { "type" => "manual" },
  status: :active,
  model: "gpt-4o-mini",
  max_tokens_per_run: 4000,
  max_tokens_per_day: 100_000,
  max_tokens_per_month: 500_000
)
agent_list_creator.save!
agent_list_creator.ai_agent_resources.find_or_create_by!(resource_type: "list") do |r|
  r.permission = :read_write
  r.description = "Create and read lists"
  r.enabled = true
end
agent_list_creator.tag_list.add("list-creation", "chat", "core")
agent_list_creator.save!
puts "✓ Created agent: List Creator Agent"

puts "\n🔮 Generating agent embeddings..."
AiAgent.all.each do |agent|
  result = EmbeddingGenerationService.call(agent)
  if result.success?
    puts "  ✓ #{agent.name}"
  else
    puts "  ⚠ #{agent.name}: #{result.message} (skipped)"
  end
end

puts "\n✅ AI Agents seeded successfully!"
puts "Available agents:"
puts "  • Task Breakdown Agent - Manual trigger, asks for goal/deadline"
puts "  • Status Report Agent - Scheduled every Monday 9am"
puts "  • List Organizer Agent - Event-triggered when items are completed"
puts "  • Research Agent - Manual trigger, enriches items with research"
puts "  • List Creator Agent - Chat integration, creates lists from requests"
