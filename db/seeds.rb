# db/seeds.rb
# Enhanced Listopia Seeds with New Polymorphic Collaboration Architecture

puts "🌱 Starting Listopia database seeding..."

# Clear existing data in development only
if Rails.env.development?
  puts "🧹 Cleaning existing data..."
  Collaborator.destroy_all
  Invitation.destroy_all
  ListItem.destroy_all
  List.destroy_all
  User.destroy_all
end

# Create Users
puts "👥 Creating users..."

mike = User.create!(
  name: "Mike Chen",
  email: "mike@listopia.com",
  password: "password123",
  email_verified_at: Time.current,
  bio: "Product manager and organization enthusiast. Always looking for better ways to manage projects and personal goals."
)

emma = User.create!(
  name: "Emma Rodriguez",
  email: "emma@listopia.com",
  password: "password123",
  email_verified_at: Time.current,
  bio: "UX designer with a passion for travel and creative projects. Believes in the power of good design and organization."
)

sarah = User.create!(
  name: "Sarah Johnson",
  email: "sarah@listopia.com",
  password: "password123",
  email_verified_at: Time.current,
  bio: "Software engineer and fitness enthusiast. Uses lists to track everything from code deployments to workout progress."
)

alex = User.create!(
  name: "Alex Thompson",
  email: "alex@listopia.com",
  password: "password123",
  email_verified_at: Time.current,
  bio: "Marketing specialist and coffee lover. Organizes campaigns, events, and weekend adventures with equal enthusiasm."
)

puts "✅ Created #{User.count} users"

# ============================================================================
# MIKE'S LISTS (1 Professional + 1 Personal)
# ============================================================================

puts "📋 Creating Mike's lists..."

# 1. Mike's Professional List - Q1 Product Roadmap
mike_pro_list = mike.lists.create!(
  title: "Q1 2025 Product Roadmap",
  description: "Strategic planning and execution for first quarter product initiatives. Focus on user experience improvements and new feature rollouts.",
  status: :active,
  list_type: :professional,
  color_theme: "blue",
  is_public: false
)

# Add diverse items to Mike's professional list
mike_pro_items = [
  { title: "Conduct user research interviews", description: "Interview 15+ users about current pain points", item_type: :task, priority: :high, due_date: 1.week.from_now },
  { title: "Launch new collaboration features", description: "Real-time editing and improved sharing capabilities", item_type: :goal, priority: :high, due_date: 6.weeks.from_now },
  { title: "API performance optimization", description: "Reduce response times by 40%", item_type: :milestone, priority: :medium, due_date: 4.weeks.from_now },
  { title: "Q1 OKR review meeting", description: "Quarterly objectives and key results assessment", item_type: :reminder, priority: :medium, due_date: 12.weeks.from_now },
  { title: "Competitor analysis report", description: "Deep dive into top 3 competitors' recent updates", item_type: :action_item, priority: :medium, due_date: 2.weeks.from_now },
  { title: "Waiting for legal review", description: "New user agreement terms pending legal approval", item_type: :waiting_for, priority: :low },
  { title: "Team retrospective insights", description: "Key takeaways from last sprint retrospective", item_type: :note, priority: :low }
]

mike_pro_items.each_with_index do |item_data, index|
  mike_pro_list.list_items.create!(item_data.merge(position: index))
end

# 2. Mike's Personal List - Health & Wellness Goals
mike_personal_list = mike.lists.create!(
  title: "2025 Health & Wellness Journey",
  description: "Personal health goals and lifestyle improvements for a better work-life balance.",
  status: :active,
  list_type: :personal,
  color_theme: "green",
  is_public: false
)

# Add health and wellness items
mike_personal_items = [
  { title: "Run 3x per week consistently", description: "Build endurance for half marathon in fall", item_type: :habit, priority: :high },
  { title: "Complete marathon training program", description: "Finish 16-week training plan for first marathon", item_type: :goal, priority: :high, due_date: 4.months.from_now },
  { title: "Weekly meal prep sessions", description: "Prepare healthy meals every Sunday", item_type: :habit, priority: :medium },
  { title: "Annual health checkup", description: "Schedule and complete yearly physical", item_type: :health, priority: :high, due_date: 1.month.from_now },
  { title: "Learn meditation techniques", description: "Complete 30-day meditation challenge", item_type: :learning, priority: :medium },
  { title: "Read 24 books this year", description: "2 books per month, mix of fiction and non-fiction", item_type: :goal, priority: :low },
  { title: "Morning workout routine", description: "20-minute morning exercises before work", item_type: :habit, priority: :medium }
]

mike_personal_items.each_with_index do |item_data, index|
  mike_personal_list.list_items.create!(item_data.merge(position: index))
end

# ============================================================================
# EMMA'S LISTS (Including Public List)
# ============================================================================

puts "🎨 Creating Emma's lists..."

# 1. Emma's Design Projects List
emma_design_list = emma.lists.create!(
  title: "UX Design Portfolio Projects",
  description: "Current design projects and portfolio development initiatives.",
  status: :active,
  list_type: :professional,
  color_theme: "purple",
  is_public: false
)

emma_design_items = [
  { title: "Redesign mobile onboarding flow", description: "Improve user activation rates by 25%", item_type: :goal, priority: :high, due_date: 3.weeks.from_now },
  { title: "Create design system documentation", description: "Document components and patterns for team", item_type: :task, priority: :medium },
  { title: "User testing session for new feature", description: "Test prototype with 8 users", item_type: :action_item, priority: :high, due_date: 1.week.from_now },
  { title: "Design team workshop on accessibility", description: "Lead session on inclusive design practices", item_type: :milestone, priority: :medium, due_date: 2.weeks.from_now },
  { title: "Portfolio website update", description: "Add recent projects and case studies", item_type: :task, priority: :low }
]

emma_design_items.each_with_index do |item_data, index|
  emma_design_list.list_items.create!(item_data.merge(position: index))
end

# 2. Emma's PUBLIC Travel List
emma_travel_list = emma.lists.create!(
  title: "Ultimate Europe Travel Guide 2025",
  description: "A comprehensive travel planning guide for backpacking through Europe. Tips, destinations, and must-see places collected from fellow travelers.",
  status: :active,
  list_type: :personal,
  color_theme: "orange",
  is_public: true,
  public_permission: :read,
  public_slug: SecureRandom.urlsafe_base64(8)
)

emma_travel_items = [
  { title: "Research visa requirements", description: "Check visa needs for all planned countries", item_type: :travel, priority: :high },
  { title: "Book flights to Amsterdam", description: "Find best deals for April departure", item_type: :travel, priority: :high, due_date: 2.weeks.from_now },
  { title: "Create packing checklist", description: "Essentials for 3-month backpacking trip", item_type: :travel, priority: :medium },
  { title: "Download offline maps", description: "Google Maps offline for all cities", item_type: :travel, priority: :medium },
  { title: "Learn basic phrases", description: "Hello, thank you, excuse me in 4 languages", item_type: :learning, priority: :low },
  { title: "Travel insurance comparison", description: "Research and purchase comprehensive coverage", item_type: :travel, priority: :high, due_date: 3.weeks.from_now },
  { title: "Hostel bookings", description: "Reserve first week of accommodations", item_type: :travel, priority: :medium },
  { title: "European train pass", description: "Purchase Eurail pass for flexible travel", item_type: :travel, priority: :medium }
]

emma_travel_items.each_with_index do |item_data, index|
  emma_travel_list.list_items.create!(item_data.merge(position: index))
end

# ============================================================================
# SARAH'S LISTS
# ============================================================================

puts "💻 Creating Sarah's lists..."

# 1. Sarah's Tech Learning List
sarah_tech_list = sarah.lists.create!(
  title: "Advanced Software Engineering Skills",
  description: "Continuous learning path for advanced software engineering concepts and emerging technologies.",
  status: :active,
  list_type: :professional,
  color_theme: "indigo",
  is_public: false
)

sarah_tech_items = [
  { title: "Master Kubernetes deployment", description: "Complete certified Kubernetes administrator course", item_type: :learning, priority: :high, due_date: 2.months.from_now },
  { title: "Contribute to open source", description: "Make meaningful contributions to Rails community", item_type: :goal, priority: :medium },
  { title: "System design interview prep", description: "Practice distributed systems architecture", item_type: :learning, priority: :high },
  { title: "Learn Rust programming", description: "Build a CLI tool in Rust for learning", item_type: :learning, priority: :low },
  { title: "Tech conference presentation", description: "Submit proposal for RailsConf 2025", item_type: :milestone, priority: :medium, due_date: 1.month.from_now },
  { title: "Mentor junior developers", description: "Volunteer for coding bootcamp mentorship", item_type: :goal, priority: :medium }
]

sarah_tech_items.each_with_index do |item_data, index|
  sarah_tech_list.list_items.create!(item_data.merge(position: index))
end

# 2. Sarah's Fitness Competition List
sarah_fitness_list = sarah.lists.create!(
  title: "Powerlifting Competition Prep",
  description: "Training plan and preparation for upcoming regional powerlifting competition.",
  status: :active,
  list_type: :personal,
  color_theme: "red",
  is_public: false
)

sarah_fitness_items = [
  { title: "Squat 2x bodyweight", description: "Current max: 225lbs, goal: 280lbs", item_type: :goal, priority: :high, due_date: 3.months.from_now },
  { title: "Weekly strength training", description: "Follow 5-day powerlifting program", item_type: :habit, priority: :high },
  { title: "Competition registration", description: "Register for Spring Regional Championships", item_type: :action_item, priority: :high, due_date: 2.weeks.from_now },
  { title: "Nutrition consultation", description: "Meet with sports nutritionist for cutting phase", item_type: :health, priority: :medium, due_date: 1.month.from_now },
  { title: "Practice competition timing", description: "Simulate competition day schedule", item_type: :task, priority: :medium },
  { title: "New powerlifting gear", description: "Belt, wrist wraps, and competition shoes", item_type: :shopping, priority: :low }
]

sarah_fitness_items.each_with_index do |item_data, index|
  sarah_fitness_list.list_items.create!(item_data.merge(position: index))
end

# ============================================================================
# ALEX'S LISTS
# ============================================================================

puts "📈 Creating Alex's lists..."

# Alex's Marketing Campaign List
alex_marketing_list = alex.lists.create!(
  title: "Q1 Marketing Campaign Strategy",
  description: "Comprehensive marketing initiatives for Q1 product launch and brand awareness.",
  status: :active,
  list_type: :professional,
  color_theme: "yellow",
  is_public: false
)

alex_marketing_items = [
  { title: "Content calendar for social media", description: "Plan 3 months of engaging content", item_type: :task, priority: :high, due_date: 1.week.from_now },
  { title: "Influencer partnership strategy", description: "Identify and reach out to micro-influencers", item_type: :action_item, priority: :medium },
  { title: "Email marketing automation", description: "Set up drip campaigns for new users", item_type: :task, priority: :medium },
  { title: "A/B test landing pages", description: "Test 3 variations for conversion optimization", item_type: :action_item, priority: :high },
  { title: "Product launch event", description: "Organize virtual launch event for new features", item_type: :milestone, priority: :high, due_date: 6.weeks.from_now }
]

alex_marketing_items.each_with_index do |item_data, index|
  alex_marketing_list.list_items.create!(item_data.merge(position: index))
end

# ============================================================================
# COLLABORATION SETUP (New Polymorphic Architecture)
# ============================================================================

puts "🤝 Setting up collaborations..."

# 1. Mike collaborates on Emma's Design Projects (write access)
emma_design_mike_collab = emma_design_list.collaborators.create!(
  user: mike,
  permission: :write
)

# 2. Mike collaborates on Sarah's Tech Learning (read access)
sarah_tech_mike_collab = sarah_tech_list.collaborators.create!(
  user: mike,
  permission: :read
)

# 3. Sarah collaborates on Mike's Professional List (write access)
mike_pro_sarah_collab = mike_pro_list.collaborators.create!(
  user: sarah,
  permission: :write
)

# 4. Add some assigned items for collaborators
# Assign some items in Mike's professional list to Sarah
mike_pro_list.list_items.limit(2).each do |item|
  item.update!(assigned_user: sarah)
end

# Assign some items in Emma's design list to Mike
emma_design_list.list_items.limit(2).each do |item|
  item.update!(assigned_user: mike)
end

# ============================================================================
# PENDING INVITATIONS
# ============================================================================

puts "📧 Creating pending invitations..."

# Emma invites a non-registered user to her travel list
travel_invitation = emma_travel_list.invitations.create!(
  email: "traveler@example.com",
  permission: :read,
  invited_by: emma,
  invitation_sent_at: 2.days.ago
)

# Sarah invites someone to her fitness list
fitness_invitation = sarah_fitness_list.invitations.create!(
  email: "coach@gym.com",
  permission: :write,
  invited_by: sarah,
  invitation_sent_at: 1.day.ago
)

# ============================================================================
# TIME TRACKING ENTRIES (Future Feature)
# ============================================================================

puts "⏱️ Adding time tracking data..."

# Add some time entries for items (showcasing upcoming time tracking feature)
mike_pro_list.list_items.completed.limit(3).each do |item|
  # Simulate time tracking for completed items
  TimeEntry.create!(
    list_item: item,
    user: mike,
    started_at: 2.hours.ago,
    ended_at: 1.hour.ago,
    duration: 1.0,
    notes: "Focused work session with good progress"
  )
end

sarah_tech_list.list_items.limit(2).each do |item|
  TimeEntry.create!(
    list_item: item,
    user: sarah,
    started_at: 3.hours.ago,
    ended_at: 1.5.hours.ago,
    duration: 1.5,
    notes: "Deep learning session"
  )
end

# ============================================================================
# RELATIONSHIPS (Future Feature - Dependencies)
# ============================================================================

puts "🔗 Creating item relationships..."

# Create some dependencies between items
# Mike's roadmap has dependency relationships
roadmap_items = mike_pro_list.list_items.limit(3).to_a
if roadmap_items.size >= 2
  Relationship.create!(
    parent: roadmap_items[0],
    child: roadmap_items[1],
    relationship_type: :dependency_finish_to_start,
    metadata: { description: "Research must complete before feature development" }
  )
end

# Sarah's competition prep has milestone dependencies
comp_items = sarah_fitness_list.list_items.limit(3).to_a
if comp_items.size >= 2
  Relationship.create!(
    parent: comp_items[0],
    child: comp_items[1],
    relationship_type: :dependency_finish_to_start,
    metadata: { description: "Strength goals must be met before competition" }
  )
end

# ============================================================================
# BOARD COLUMNS (Kanban-style organization)
# ============================================================================

puts "📊 Setting up board columns..."

# Create default board columns for a few lists
[ mike_pro_list, emma_design_list, sarah_tech_list ].each do |list|
  %w[Backlog In\ Progress Review Done].each_with_index do |column_name, index|
    list.board_columns.create!(
      name: column_name,
      position: index,
      metadata: { color: %w[gray blue yellow green][index] }
    )
  end
end

# ============================================================================
# COMPLETE SOME ITEMS FOR REALISTIC DATA
# ============================================================================

puts "✅ Completing some items for realistic progress..."

# Complete some items across different lists to show progress
all_lists = [ mike_pro_list, mike_personal_list, emma_design_list, emma_travel_list,
             sarah_tech_list, sarah_fitness_list, alex_marketing_list ]

all_lists.each do |list|
  # Complete roughly 30% of items in each list
  items_to_complete = list.list_items.limit((list.list_items.count * 0.3).round)
  items_to_complete.each do |item|
    item.update!(
      completed: true,
      completed_at: rand(1..10).days.ago
    )
  end
end

# ============================================================================
# SUMMARY
# ============================================================================

puts "\n🎉 Seeding completed successfully!"
puts "=" * 50
puts "📊 SUMMARY:"
puts "Users created: #{User.count}"
puts "Lists created: #{List.count}"
puts "  - Professional lists: #{List.list_type_professional.count}"
puts "  - Personal lists: #{List.list_type_personal.count}"
puts "  - Public lists: #{List.where(is_public: true).count}"
puts "List items created: #{ListItem.count}"
puts "  - Completed items: #{ListItem.completed.count}"
puts "  - Pending items: #{ListItem.pending.count}"
puts "Collaborations: #{Collaborator.count}"
puts "Pending invitations: #{Invitation.pending.count}"
puts "Time entries: #{TimeEntry.count}"
puts "Item relationships: #{Relationship.count}"
puts "Board columns: #{BoardColumn.count}"
puts "\n👥 USER ACCESS:"
puts "• Mike (mike@listopia.com): 2 lists + collaborator on 2 others"
puts "• Emma (emma@listopia.com): 2 lists (1 public) + 1 collaboration"
puts "• Sarah (sarah@listopia.com): 2 lists + collaborator on 1 other"
puts "• Alex (alex@listopia.com): 1 list"
puts "\n🔐 All user passwords: password123"
puts "🌐 Public list: #{emma_travel_list.title} (slug: #{emma_travel_list.public_slug})"
puts "\n✨ Ready to explore Listopia's new polymorphic collaboration features!"
