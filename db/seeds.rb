# db/seeds.rb
puts "🌱 Starting to seed Listopia database..."

# Clear existing data in development
if Rails.env.development?
  puts "🧹 Cleaning existing data..."
  ListItem.destroy_all
  ListCollaboration.destroy_all
  List.destroy_all
  User.destroy_all
end

# Create Users
puts "👥 Creating users..."

admin = User.create!(
  name: "Admin User",
  email: "admin@listopia.com",
  password: "password123",
  password_confirmation: "password123",
  email_verified_at: Time.current
)

sarah = User.create!(
  name: "Sarah Johnson",
  email: "sarah@example.com",
  password: "password123",
  password_confirmation: "password123",
  email_verified_at: Time.current,
  bio: "Travel enthusiast and project manager"
)

mike = User.create!(
  name: "Mike Chen",
  email: "mike@example.com",
  password: "password123",
  password_confirmation: "password123",
  email_verified_at: Time.current,
  bio: "Software developer who loves cooking"
)

emma = User.create!(
  name: "Emma Wilson",
  email: "emma@example.com",
  password: "password123",
  password_confirmation: "password123",
  email_verified_at: Time.current,
  bio: "Product designer and organization enthusiast"
)

puts "✅ Created #{User.count} users"

# 1. VACATION PLANNING LIST
puts "✈️ Creating vacation planning list..."

vacation_list = sarah.lists.create!(
  title: "🏖️ Summer Vacation to Hawaii",
  description: "Planning our 10-day trip to Maui and Oahu. Need to book everything and pack appropriately for hiking and beaches.",
  status: :active,
  color_theme: "blue",
  is_public: false
)

# Vacation list items
vacation_items = [
  {
    title: "Book round-trip flights to Honolulu",
    description: "Looking for flights departing June 15th, returning June 25th. Prefer morning departures.",
    item_type: :task,
    priority: :urgent,
    due_date: 1.week.from_now,
    url: "https://www.kayak.com",
    metadata: { estimated_cost: "$800 per person", notes: "Check for deals on Tuesday/Wednesday" }
  },
  {
    title: "Reserve rental car in Maui",
    description: "Need 4WD for Road to Hana. Pick up at Kahului Airport.",
    item_type: :task,
    priority: :high,
    due_date: 10.days.from_now,
    url: "https://www.enterprise.com",
    metadata: { estimated_cost: "$400 for 5 days" }
  },
  {
    title: "Book Airbnb in Wailea",
    description: "Ocean view, 2BR/2BA, close to beaches. Check cancellation policy.",
    item_type: :task,
    priority: :high,
    due_date: 5.days.from_now,
    url: "https://www.airbnb.com",
    metadata: { estimated_cost: "$200/night", preferred_area: "South Maui" }
  },
  {
    title: "Hiking boots (waterproof)",
    description: "For Haleakala crater and bamboo forest hikes",
    item_type: :task,
    priority: :medium,
    metadata: { store: "REI or local outdoor store", size: "US 8" }
  },
  {
    title: "Snorkeling gear",
    description: "Mask, snorkel, fins for Molokini crater",
    item_type: :task,
    priority: :medium,
    metadata: { option: "rent locally or buy cheap set" }
  },
  {
    title: "Reef-safe sunscreen",
    description: "Hawaii requires mineral sunscreen only",
    item_type: :task,
    priority: :medium,
    metadata: { brands: "Blue Lizard, Badger, or local Hawaii brands" }
  },
  {
    title: "Research Road to Hana stops",
    description: "Plan stops for waterfalls, food trucks, and scenic viewpoints",
    item_type: :note,
    priority: :low,
    metadata: {
      key_stops: "Twin Falls, Wai'anapanapa State Park, Hana Bay",
      tips: "Start early, bring snacks, download offline maps"
    }
  },
  {
    title: "Pack beach essentials",
    description: "Swimwear, cover-ups, beach towels, waterproof phone case",
    item_type: :task,
    priority: :low,
    due_date: 2.days.before(vacation_list.created_at + 3.weeks)
  },
  {
    title: "Download offline maps",
    description: "Google Maps offline for Maui and Oahu",
    item_type: :task,
    priority: :low,
    metadata: { apps: "Google Maps, Maps.me for hiking trails" }
  },
  {
    title: "Travel insurance confirmation",
    description: "Verify coverage for activities and rental car",
    item_type: :file,
    priority: :medium,
    url: "https://www.worldnomads.com"
  }
]

vacation_items.each_with_index do |item_attrs, index|
  vacation_list.list_items.create!(
    item_attrs.merge(
      position: index,
      completed: [ true, false, false, true, false, false, false, false, false, false ][index]
    )
  )
end

# Add collaboration
vacation_list.add_collaborator(mike, permission: 'collaborate')

puts "✅ Created vacation list with #{vacation_list.list_items.count} items"

# 2. GROCERY SHOPPING LIST
puts "🛒 Creating grocery shopping list..."

grocery_list = mike.lists.create!(
  title: "🥕 Weekly Grocery Shopping",
  description: "Shopping for the family dinner party this weekend plus regular weekly essentials.",
  status: :active,
  color_theme: "green",
  is_public: false
)

grocery_items = [
  {
    title: "Eggs (dozen, organic)",
    description: "Free-range if possible",
    item_type: :task,
    priority: :medium,
    metadata: {
      quantity: "1 dozen",
      brand_preference: "Vital Farms or local",
      store: "Any grocery store"
    }
  },
  {
    title: "Milk (1L, whole)",
    description: "Glass bottle preferred",
    item_type: :task,
    priority: :medium,
    metadata: {
      quantity: "1 liter",
      type: "whole milk",
      store: "Whole Foods (glass bottles) or regular grocery"
    }
  },
  {
    title: "Small Coke cans (12-pack)",
    description: "For the party, diet and regular mix",
    item_type: :task,
    priority: :low,
    metadata: {
      quantity: "2 packs (1 diet, 1 regular)",
      size: "12 fl oz cans",
      store: "Any grocery store"
    }
  },
  {
    title: "Gummy bears",
    description: "Haribo if available",
    item_type: :task,
    priority: :low,
    metadata: {
      quantity: "2 bags",
      brand: "Haribo preferred",
      store: "Candy aisle or Target"
    }
  },
  {
    title: "Ground beef (2 lbs, 80/20)",
    description: "For burgers and tacos",
    item_type: :task,
    priority: :high,
    metadata: {
      quantity: "2 pounds",
      fat_content: "80/20 lean",
      store: "Butcher shop preferred, or grocery meat counter"
    }
  },
  {
    title: "Truffle oil",
    description: "For the special pasta dish",
    item_type: :task,
    priority: :medium,
    metadata: {
      quantity: "1 small bottle",
      type: "white truffle oil",
      store: "Whole Foods or gourmet section only",
      note: "Expensive item - only at specialty stores"
    }
  },
  {
    title: "Fresh basil (large pack)",
    description: "For caprese and pasta",
    item_type: :task,
    priority: :medium,
    metadata: {
      quantity: "1 large pack or 2 small",
      freshness: "bright green, no wilting",
      store: "Any grocery store"
    }
  },
  {
    title: "Sourdough bread (artisan)",
    description: "From the bakery section",
    item_type: :task,
    priority: :medium,
    metadata: {
      quantity: "1 loaf",
      type: "sourdough, crusty exterior",
      store: "Bakery section or local bakery"
    }
  },
  {
    title: "Aged balsamic vinegar",
    description: "12+ year aged for the salad",
    item_type: :task,
    priority: :low,
    metadata: {
      quantity: "1 bottle",
      age: "12+ years preferred",
      store: "Whole Foods, Williams Sonoma, or gourmet store only"
    }
  },
  {
    title: "Ice cream (vanilla bean)",
    description: "Premium brand for dessert",
    item_type: :task,
    priority: :low,
    metadata: {
      quantity: "1 pint",
      flavor: "vanilla bean (real vanilla)",
      brand: "Häagen-Dazs or Ben & Jerry's"
    }
  }
]

grocery_items.each_with_index do |item_attrs, index|
  grocery_list.list_items.create!(
    item_attrs.merge(
      position: index,
      completed: [ true, true, false, false, true, false, true, false, false, false ][index]
    )
  )
end

# Add collaboration
grocery_list.add_collaborator(emma, permission: 'read')

puts "✅ Created grocery list with #{grocery_list.list_items.count} items"

# 3. PROJECT MANAGEMENT LIST
puts "💼 Creating project management list..."

project_list = emma.lists.create!(
  title: "🚀 Q2 Mobile App Redesign",
  description: "Complete redesign of our mobile application UI/UX with new branding and improved user experience. Target launch: end of Q2.",
  status: :active,
  color_theme: "purple",
  is_public: false
)

project_items = [
  {
    title: "Stakeholder kickoff meeting",
    description: "Align on project goals, timeline, and success metrics with all stakeholders",
    item_type: :task,
    priority: :urgent,
    due_date: 2.days.ago,
    assigned_user: emma,
    metadata: {
      meeting_type: "In-person conference room",
      attendees: "Product, Design, Engineering, Marketing",
      duration: "2 hours"
    },
    completed: true,
    completed_at: 2.days.ago
  },
  {
    title: "User research & persona analysis",
    description: "Conduct user interviews and analyze current user behavior patterns",
    item_type: :task,
    priority: :high,
    due_date: 1.week.from_now,
    assigned_user: emma,
    metadata: {
      participants: "20 current users across demographics",
      methods: "interviews, surveys, analytics review",
      deliverable: "User persona document"
    }
  },
  {
    title: "Competitive analysis report",
    description: "Analyze top 5 competitors' mobile apps and document best practices",
    item_type: :file,
    priority: :high,
    due_date: 1.week.from_now,
    url: "https://docs.google.com/document/d/competitive-analysis",
    metadata: {
      competitors: "Instagram, TikTok, Snapchat, Pinterest, Twitter",
      focus_areas: "Navigation, onboarding, content discovery"
    }
  },
  {
    title: "Create wireframes for key screens",
    description: "Low-fidelity wireframes for home, profile, search, and content creation flows",
    item_type: :task,
    priority: :high,
    due_date: 2.weeks.from_now,
    assigned_user: emma,
    metadata: {
      tool: "Figma",
      screens: "~15 key screens",
      review_cycle: "2 rounds with stakeholders"
    }
  },
  {
    title: "Design system updates",
    description: "Update color palette, typography, and component library for new brand",
    item_type: :task,
    priority: :medium,
    due_date: 3.weeks.from_now,
    metadata: {
      components: "buttons, cards, forms, navigation",
      accessibility: "WCAG 2.1 AA compliance",
      tool: "Figma design system"
    }
  },
  {
    title: "High-fidelity mockups",
    description: "Pixel-perfect designs with final colors, images, and micro-interactions",
    item_type: :task,
    priority: :high,
    due_date: 4.weeks.from_now,
    assigned_user: emma,
    metadata: {
      deliverable: "Complete Figma prototype",
      interactions: "Tap, swipe, scroll animations",
      review_stakeholders: "Product, Engineering, CEO"
    }
  },
  {
    title: "Usability testing sessions",
    description: "Test new designs with 10 users before development starts",
    item_type: :task,
    priority: :medium,
    due_date: 5.weeks.from_now,
    metadata: {
      participants: "10 target users",
      method: "moderated remote testing",
      duration: "45 min per session"
    }
  },
  {
    title: "Technical feasibility review",
    description: "Engineering review of designs for implementation complexity",
    item_type: :task,
    priority: :high,
    due_date: 4.weeks.from_now,
    assigned_user: mike,
    metadata: {
      focus: "animation performance, API requirements",
      timeline: "development effort estimation",
      platform: "iOS and Android considerations"
    }
  },
  {
    title: "Development handoff documentation",
    description: "Detailed specs, assets, and interaction documentation for developers",
    item_type: :file,
    priority: :medium,
    due_date: 6.weeks.from_now,
    url: "https://www.notion.so/dev-handoff-specs",
    metadata: {
      includes: "Figma dev mode, asset exports, animation specs",
      format: "Notion documentation + Figma comments"
    }
  },
  {
    title: "QA testing plan",
    description: "Comprehensive testing strategy for the new designs across devices",
    item_type: :task,
    priority: :low,
    due_date: 7.weeks.from_now,
    metadata: {
      devices: "iPhone 12-15, Android flagship + budget",
      scenarios: "Happy path + edge cases",
      accessibility: "VoiceOver and TalkBack testing"
    }
  },
  {
    title: "Launch metrics dashboard",
    description: "Set up analytics to measure success of the redesign",
    item_type: :task,
    priority: :low,
    due_date: 8.weeks.from_now,
    metadata: {
      metrics: "user engagement, conversion rates, task completion",
      tools: "Google Analytics, Mixpanel, Hotjar",
      baseline: "current metrics for comparison"
    }
  },
  {
    title: "Marketing assets for launch",
    description: "App store screenshots, social media assets, and press kit",
    item_type: :task,
    priority: :low,
    due_date: 9.weeks.from_now,
    metadata: {
      deliverables: "App store assets, social media templates",
      coordination: "Work with marketing team",
      timeline: "2 weeks before app store submission"
    }
  }
]

project_items.each_with_index do |item_attrs, index|
  item = project_list.list_items.create!(
    item_attrs.merge(position: index)
  )

  # Mark first item as completed since it's in the past
  if index == 0
    item.update!(completed: true, completed_at: item_attrs[:completed_at])
  end
end

# Add collaborations
project_list.add_collaborator(sarah, permission: 'collaborate')
project_list.add_collaborator(mike, permission: 'collaborate')

puts "✅ Created project management list with #{project_list.list_items.count} items"

# 4. CREATE SOME ADDITIONAL LISTS FOR VARIETY
puts "📋 Creating additional sample lists..."

# Simple completed list
completed_list = admin.lists.create!(
  title: "✅ Weekend Chores",
  description: "Saturday morning cleanup and organization",
  status: :completed,
  color_theme: "green"
)

weekend_chores = [
  "Clean bathroom",
  "Vacuum living room",
  "Do laundry",
  "Grocery shopping",
  "Water plants"
]

weekend_chores.each_with_index do |title, index|
  completed_list.list_items.create!(
    title: title,
    item_type: :task,
    priority: :medium,
    position: index,
    completed: true,
    completed_at: 1.day.ago
  )
end

# Public reading list
reading_list = sarah.lists.create!(
  title: "📚 2024 Reading List",
  description: "Books I want to read this year - feel free to suggest more!",
  status: :active,
  color_theme: "yellow",
  is_public: true
)

books = [
  { title: "The Seven Husbands of Evelyn Hugo", author: "Taylor Jenkins Reid" },
  { title: "Atomic Habits", author: "James Clear" },
  { title: "Project Hail Mary", author: "Andy Weir" },
  { title: "The Midnight Library", author: "Matt Haig" },
  { title: "Educated", author: "Tara Westover" }
]

books.each_with_index do |book, index|
  reading_list.list_items.create!(
    title: book[:title],
    description: "by #{book[:author]}",
    item_type: :note,
    priority: :low,
    position: index,
    completed: index < 2 # First 2 books completed
  )
end

puts "✅ Created additional sample lists"

# Print summary
puts "\n🎉 Seed completed successfully!"
puts "\n📊 Summary:"
puts "👥 Users: #{User.count}"
puts "📋 Lists: #{List.count}"
puts "📝 List Items: #{ListItem.count}"
puts "🤝 Collaborations: #{ListCollaboration.count}"
puts "\n🔐 Login credentials:"
puts "Email: admin@listopia.com | Password: password123"
puts "Email: sarah@example.com | Password: password123"
puts "Email: mike@example.com | Password: password123"
puts "Email: emma@example.com | Password: password123"
puts "\n🌟 Happy organizing with Listopia!"
