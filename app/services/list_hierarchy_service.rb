# app/services/list_hierarchy_service.rb
#
# DEPRECATED: This service is deprecated in favor of ListCreationService#create_list_with_structure
#
# ListCreationService now handles all list creation including nested hierarchies.
# This service will be removed in a future release.
#
# Use ListCreationService instead:
#   service = ListCreationService.new(user)
#   result = service.create_list_with_structure(
#     title: "US Roadshow",
#     nested_lists: [
#       {title: "New York", items: [...]},
#       {title: "Chicago", items: [...]}
#     ]
#   )
#
# Service for creating hierarchical nested lists
# Handles parent-child relationships between lists
# Organizes items into logical groupings (locations, phases, categories, etc.)
#
# Example: Roadshow planning with per-location sub-lists
#   Main List: "US Roadshow"
#   ├── Sub-list: "Pre-Roadshow"
#   ├── Sub-list: "New York"
#   │   ├── Venue booking
#   │   ├── Marketing
#   │   └── Follow-up
#   ├── Sub-list: "Chicago"
#   │   ├── Venue booking
#   │   ├── Marketing
#   │   └── Follow-up
#   └── Sub-list: "Post-Roadshow"

class ListHierarchyService < ApplicationService
  def initialize(parent_list:, nested_structures:, created_by_user:, created_in_organization:)
    @parent_list = parent_list
    @nested_structures = nested_structures
    @created_by_user = created_by_user
    @created_in_organization = created_in_organization
  end

  def call
    created_sublists = []
    errors = []

    begin
      # Create sub-lists from nested structures
      @nested_structures.each do |sub_structure|
        result = create_sublist(sub_structure)

        if result.success?
          created_sublists << result.data[:sublist]
        else
          errors.concat(result.errors)
        end
      end

      if created_sublists.present?
        success(data: {
          parent_list: @parent_list,
          sublists: created_sublists,
          sublists_count: created_sublists.count,
          errors: errors
        })
      elsif errors.present?
        failure(errors: errors)
      else
        success(data: {
          parent_list: @parent_list,
          sublists: [],
          sublists_count: 0,
          errors: []
        })
      end
    rescue => e
      Rails.logger.error("List hierarchy creation failed: #{e.message}")
      failure(errors: [ e.message ])
    end
  end

  private

  # Create a single sub-list
  def create_sublist(structure)
    title = structure.is_a?(Hash) ? (structure["title"] || structure[:title]) : structure.to_s
    items_data = structure.is_a?(Hash) ? (structure["items"] || structure[:items] || []) : []
    description = structure.is_a?(Hash) ? (structure["description"] || structure[:description]) : nil

    return failure(errors: [ "Sub-list title is required" ]) unless title.present?

    # Create the sub-list
    sublist = List.new(
      organization: @created_in_organization,
      owner: @created_by_user,
      parent_list: @parent_list,
      title: title,
      description: description,
      status: @parent_list.status,
      list_type: @parent_list.list_type,
      team_id: @parent_list.team_id
    )

    unless sublist.save
      return failure(errors: sublist.errors.full_messages)
    end

    # Create items for this sub-list
    items_created = 0
    items_list = []

    items_data.each_with_index do |item_data, index|
      item_title = item_data.is_a?(Hash) ? (item_data["title"] || item_data[:title]) : item_data.to_s
      next unless item_title.present?

      list_item = ListItem.new(
        list: sublist,
        title: item_title,
        description: item_data.is_a?(Hash) ? (item_data["description"] || item_data[:description]) : nil,
        status: "pending",
        position: index,
        assigned_user_id: nil
      )

      if list_item.save
        items_created += 1
        items_list << item_title
      end
    end

    success(data: {
      sublist: sublist,
      items_created: items_created,
      items: items_list
    })
  rescue => e
    Rails.logger.error("Sub-list creation failed: #{e.message}")
    failure(errors: [ e.message ])
  end
end
