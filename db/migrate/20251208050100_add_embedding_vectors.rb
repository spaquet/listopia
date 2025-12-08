class AddEmbeddingVectors < ActiveRecord::Migration[8.0]
  def change
    # Enable pgvector extension
    enable_extension 'vector'

    # ===== Lists =====
    add_column :lists, :embedding, :vector, limit: 1536, unless column_exists?(:lists, :embedding)
    add_index :lists, :embedding, using: :ivfflat, opclass: :vector_cosine_ops, if_not_exists: true
    add_column :lists, :embedding_generated_at, :datetime, unless column_exists?(:lists, :embedding_generated_at)
    add_column :lists, :requires_embedding_update, :boolean, default: false, unless column_exists?(:lists, :requires_embedding_update)

    # ===== ListItems =====
    add_column :list_items, :embedding, :vector, limit: 1536, unless column_exists?(:list_items, :embedding)
    add_index :list_items, :embedding, using: :ivfflat, opclass: :vector_cosine_ops, if_not_exists: true
    add_column :list_items, :embedding_generated_at, :datetime, unless column_exists?(:list_items, :embedding_generated_at)
    add_column :list_items, :requires_embedding_update, :boolean, default: false, unless column_exists?(:list_items, :requires_embedding_update)

    # ===== Comments =====
    add_column :comments, :embedding, :vector, limit: 1536, unless column_exists?(:comments, :embedding)
    add_index :comments, :embedding, using: :ivfflat, opclass: :vector_cosine_ops, if_not_exists: true
    add_column :comments, :embedding_generated_at, :datetime, unless column_exists?(:comments, :embedding_generated_at)
    add_column :comments, :requires_embedding_update, :boolean, default: false, unless column_exists?(:comments, :requires_embedding_update)

    # ===== Tags (from acts-as-taggable-on gem) =====
    # Note: Tags table already exists from the gem, we just add embedding support
    add_column :tags, :embedding, :vector, limit: 1536, unless column_exists?(:tags, :embedding)
    add_index :tags, :embedding, using: :ivfflat, opclass: :vector_cosine_ops, if_not_exists: true
    add_column :tags, :embedding_generated_at, :datetime, unless column_exists?(:tags, :embedding_generated_at)
    add_column :tags, :requires_embedding_update, :boolean, default: false, unless column_exists?(:tags, :requires_embedding_update)
  end
end
