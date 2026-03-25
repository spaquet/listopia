# app/schemas/item_schema.rb
# Schema for generated list items
# Ensures items always have: title, description, type, priority

class ItemSchema < RubyLLM::Schema
  array :items do
    object do
      string :title, description: "The item title or name"
      string :description, description: "Why this item is good/relevant (1-2 sentences)"
      string :type,
             enum: [ "task", "section" ],
             description: "Item type: 'task' for action items, 'section' for category headers"
      string :priority,
             enum: [ "high", "medium", "low" ],
             description: "Priority level"
    end
  end
end
