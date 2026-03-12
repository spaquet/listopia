# app/models/list_collaboration.rb
# Alias class for polymorphic Collaborator when collaboratable is a List
# Used for semantic clarity and backward compatibility
class ListCollaboration
  def self.count
    Collaborator.where(collaboratable_type: "List").count
  end

  def self.where(*args)
    Collaborator.where(collaboratable_type: "List")
  end

  def self.exists?(id)
    Collaborator.exists?(id: id, collaboratable_type: "List")
  end
end
