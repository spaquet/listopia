class AddFulltextSearchSupport < ActiveRecord::Migration[8.0]
  def change
    # ===== Lists Full-Text Search =====
    add_column :lists, :search_document, :tsvector, unless column_exists?(:lists, :search_document)
    add_index :lists, :search_document, using: :gin, if_not_exists: true

    # ===== ListItems Full-Text Search =====
    add_column :list_items, :search_document, :tsvector, unless column_exists?(:list_items, :search_document)
    add_index :list_items, :search_document, using: :gin, if_not_exists: true

    # ===== Comments Full-Text Search =====
    add_column :comments, :search_document, :tsvector, unless column_exists?(:comments, :search_document)
    add_index :comments, :search_document, using: :gin, if_not_exists: true

    # ===== Tags Full-Text Search =====
    add_column :tags, :search_document, :tsvector, unless column_exists?(:tags, :search_document)
    add_index :tags, :search_document, using: :gin, if_not_exists: true
  end
end
