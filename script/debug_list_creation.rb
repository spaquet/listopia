# Debug script to test list creation
# Run this in Rails console to verify the fixes work

# In Rails console:
# load 'script/debug_list_creation.rb'

puts "=== Testing List Creation Fixes ==="

# Find a user to test with
user = User.first
if user.nil?
  puts "❌ No users found. Please create a user first."
  exit
end

puts "✅ Testing with user: #{user.email}"

# Test 1: Regular list creation
puts "\n--- Test 1: Regular List Creation ---"
initial_count = user.lists.count
puts "Initial list count: #{initial_count}"

service = ListCreationService.new(user)
result = service.create_list(title: "Test Regular List", description: "Testing regular creation")

if result.success?
  final_count = user.lists.count
  puts "✅ Regular list created successfully"
  puts "✅ Final list count: #{final_count}"
  puts "✅ Created exactly 1 list: #{final_count - initial_count == 1}"

  list = result.data
  puts "✅ List ID: #{list.id}"
  puts "✅ List title: #{list.title}"
  puts "✅ List items count: #{list.list_items.count}"
else
  puts "❌ Failed to create regular list: #{result.errors.join(', ')}"
end

# Test 2: Planning list creation
puts "\n--- Test 2: Planning List Creation ---"
initial_count = user.lists.count
puts "Initial list count: #{initial_count}"

service = ListCreationService.new(user)
result = service.create_planning_list(
  title: "Test Conference Planning",
  description: "Testing planning list creation",
  planning_context: "conference"
)

if result.success?
  final_count = user.lists.count
  puts "✅ Planning list created successfully"
  puts "✅ Final list count: #{final_count}"
  puts "✅ Created exactly 1 list: #{final_count - initial_count == 1}"

  list = result.data
  list.reload # Ensure we have latest data

  puts "✅ List ID: #{list.id}"
  puts "✅ List title: #{list.title}"
  puts "✅ List items count: #{list.list_items.count}"
  puts "✅ Planning items created: #{list.list_items.count > 0}"

  if list.list_items.count > 0
    puts "\n📋 Created items:"
    list.list_items.order(:position).each_with_index do |item, index|
      puts "  #{index + 1}. #{item.title} (#{item.item_type}, #{item.priority})"
    end
  end
else
  puts "❌ Failed to create planning list: #{result.errors.join(', ')}"
end

# Test 3: ListManagementTool
puts "\n--- Test 3: ListManagementTool ---"
initial_count = user.lists.count
puts "Initial list count: #{initial_count}"

tool = ListManagementTool.new(user)
result = tool.execute(
  action: "create_planning_list",
  title: "Tool Test Conference",
  planning_context: "conference"
)

if result[:success]
  final_count = user.lists.count
  puts "✅ Tool planning list created successfully"
  puts "✅ Final list count: #{final_count}"
  puts "✅ Created exactly 1 list: #{final_count - initial_count == 1}"

  list_data = result[:list]
  puts "✅ List ID: #{list_data[:id]}"
  puts "✅ List title: #{list_data[:title]}"
  puts "✅ Items count: #{list_data[:items_count]}"

  if result[:items]
    puts "\n📋 Tool created items:"
    result[:items].each_with_index do |item, index|
      puts "  #{index + 1}. #{item[:title]} (#{item[:type]}, #{item[:priority]})"
    end
  end
else
  puts "❌ Failed to create tool planning list: #{result[:error]}"
end

puts "\n=== Test Summary ==="
puts "If all tests show ✅ and 'Created exactly 1 list: true', then the fixes are working!"
puts "If any test shows 'Created exactly 1 list: false', there are still duplication issues."
