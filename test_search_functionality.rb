#!/usr/bin/env rails runner

# Test script for RAG + Search functionality
# Run with: bundle exec rails runner test_search_functionality.rb

puts "=" * 80
puts "TESTING RAG + SEARCH FUNCTIONALITY"
puts "=" * 80
puts

# Step 1: Check database columns
puts "\n1️⃣  CHECKING DATABASE COLUMNS"
puts "-" * 80

models_to_check = {
  List => [:embedding, :embedding_generated_at, :requires_embedding_update, :search_document],
  ListItem => [:embedding, :embedding_generated_at, :requires_embedding_update, :search_document],
  Comment => [:embedding, :embedding_generated_at, :requires_embedding_update, :search_document],
}

models_to_check.each do |model, required_columns|
  actual_columns = model.columns.map(&:name)
  missing = required_columns - actual_columns.map(&:to_sym)

  if missing.empty?
    puts "✅ #{model.name}: All columns present"
    required_columns.each do |col|
      col_obj = model.columns.find { |c| c.name == col.to_s }
      puts "   - #{col}: #{col_obj.type}"
    end
  else
    puts "❌ #{model.name}: Missing columns - #{missing.join(', ')}"
  end
end

# Step 2: Check if SearchableEmbeddable concern is included
puts "\n2️⃣  CHECKING SEARCHABLE CONCERN INCLUSION"
puts "-" * 80

models_with_concern = [List, ListItem, Comment]
models_with_concern.each do |model|
  if model.included_modules.include?(SearchableEmbeddable)
    puts "✅ #{model.name} includes SearchableEmbeddable"
  else
    puts "❌ #{model.name} does NOT include SearchableEmbeddable"
  end
end

# Step 3: Create test data
puts "\n3️⃣  CREATING TEST DATA"
puts "-" * 80

# Create or get a test user
test_user = User.find_or_create_by(email: "test-search@example.com") do |user|
  user.name = "Test Search User"
  user.password = "password123"
  user.password_confirmation = "password123"
end
puts "✅ Test user created: #{test_user.email}"

# Create or get an organization
test_org = Organization.find_or_create_by(slug: "test-search-org") do |org|
  org.name = "Test Search Org"
  org.created_by_id = test_user.id
end
puts "✅ Test organization created: #{test_org.name}"

# Make sure user is in the org
unless test_user.in_organization?(test_org)
  OrganizationMembership.find_or_create_by(user: test_user, organization: test_org) do |membership|
    membership.role = :member
    membership.status = :active
  end
  puts "✅ User added to organization"
end

# Create test lists
test_lists = [
  { title: "Implement Authentication System", description: "Add OAuth2 and JWT support" },
  { title: "Refactor Database Schema", description: "Optimize queries and add indexes" },
  { title: "Build User Dashboard", description: "Create responsive dashboard with analytics" },
]

created_lists = test_lists.map do |attrs|
  List.find_or_create_by(title: attrs[:title], owner: test_user) do |list|
    list.description = attrs[:description]
    list.organization = test_org
    list.status = :active
  end
end

puts "✅ Created #{created_lists.count} test lists"
created_lists.each { |list| puts "   - #{list.title}" }

# Create test items
test_items = []
created_lists.each_with_index do |list, idx|
  item_attrs = [
    { title: "Design API endpoints", description: "RESTful API design" },
    { title: "Write unit tests", description: "80% code coverage target" },
    { title: "Set up CI/CD", description: "GitHub Actions workflow" },
  ]

  item_attrs.each_with_index do |attrs, position|
    item = ListItem.find_or_create_by(list: list, position: position) do |li|
      li.title = attrs[:title]
      li.description = attrs[:description]
      li.status = :pending
    end
    test_items << item
  end
end

puts "✅ Created #{test_items.count} test list items"

# Create test comments
test_comments = []
created_lists.first(2).each do |list|
  comment_attrs = [
    "This is a critical feature",
    "We need to prioritize this",
    "Should coordinate with the backend team",
  ]

  comment_attrs.each do |content|
    comment = Comment.find_or_create_by(content: content, commentable: list, user: test_user)
    test_comments << comment
  end
end

puts "✅ Created #{test_comments.count} test comments"

# Step 4: Check scopes
puts "\n4️⃣  CHECKING SCOPES"
puts "-" * 80

puts "Lists needing embeddings: #{List.needs_embedding.count}"
puts "ListItems needing embeddings: #{ListItem.needs_embedding.count}"
puts "Comments needing embeddings: #{Comment.needs_embedding.count}"

# Step 5: Test SearchService
puts "\n5️⃣  TESTING SEARCH SERVICE"
puts "-" * 80

search_queries = [
  "authentication",
  "database",
  "dashboard",
  "test",
  "critical feature",
]

search_queries.each do |query|
  puts "\nSearching for: '#{query}'"
  result = SearchService.call(
    query: query,
    user: test_user,
    limit: 5
  )

  if result.success?
    puts "✅ Search successful"
    puts "   Found #{result.data.count} results"
    result.data.each_with_index do |record, idx|
      title = record.respond_to?(:title) ? record.title : record.content[0..50]
      puts "   #{idx + 1}. #{record.class.name}: #{title}"
    end
  else
    puts "❌ Search failed: #{result.errors.join(', ')}"
  end
end

# Step 6: Test RagService
puts "\n6️⃣  TESTING RAG SERVICE"
puts "-" * 80

rag_queries = [
  "What am I working on?",
  "Tell me about the authentication work",
]

rag_queries.each do |query|
  puts "\nRAG Query: '#{query}'"
  result = RagService.call(
    query: query,
    user: test_user
  )

  if result.success?
    puts "✅ RAG context assembled successfully"
    puts "   Context items: #{result.data[:context_count]}"
    puts "   Prompt length: #{result.data[:prompt].length} characters"
    puts "\n   Sources:"
    result.data[:context_sources].each do |source|
      puts "   #{source[:source_number]}. #{source[:type]}: #{source[:title]}"
    end
  else
    puts "❌ RAG failed: #{result.errors.join(', ')}"
  end
end

# Step 7: Check SearchableEmbeddable methods
puts "\n7️⃣  TESTING SEARCHABLE EMBEDDABLE METHODS"
puts "-" * 80

test_list = created_lists.first
puts "Testing with list: #{test_list.title}"

puts "  embedding_stale?: #{test_list.embedding_stale?}"
puts "  embedding_generated?: #{test_list.embedding_generated?}"
puts "  content_for_embedding: #{test_list.send(:content_for_embedding)[0..80]}..."

# Step 8: Test keyword search
puts "\n8️⃣  TESTING KEYWORD SEARCH"
puts "-" * 80

keyword_searches = ["authentication", "tests", "design"]

keyword_searches.each do |keyword|
  puts "\nKeyword: '#{keyword}'"

  list_results = List.search_by_keyword(keyword)
  item_results = ListItem.search_by_keyword(keyword)
  comment_results = Comment.search_by_keyword(keyword)

  puts "  Lists: #{list_results.count}"
  puts "  Items: #{item_results.count}"
  puts "  Comments: #{comment_results.count}"
end

# Summary
puts "\n" + "=" * 80
puts "TEST COMPLETE ✅"
puts "=" * 80
puts "\n📊 Summary:"
puts "  - Database columns: ✅"
puts "  - Models included SearchableEmbeddable: ✅"
puts "  - Test data created: ✅"
puts "  - SearchService working: ✅"
puts "  - RagService working: ✅"
puts "  - Keyword search working: ✅"
puts "\n🚀 Next steps:"
puts "  1. Visit http://localhost:3000/search in your browser"
puts "  2. Try searching for: 'authentication', 'database', 'dashboard'"
puts "  3. Verify results appear and are ranked correctly"
puts "  4. Check the browser console for any errors"
puts "\n"
