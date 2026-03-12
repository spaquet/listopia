# app/models/list_item_collaboration.rb
# Alias class for polymorphic Collaborator when collaboratable is a ListItem
# Used for semantic clarity and backward compatibility
class ListItemCollaboration
  def self.count
    Collaborator.where(collaboratable_type: "ListItem").count
  end

  def self.where(*args)
    Collaborator.where(collaboratable_type: "ListItem")
  end
end
