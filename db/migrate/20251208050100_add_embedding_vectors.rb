class AddEmbeddingVectors < ActiveRecord::Migration[8.0]
  def change
    # Enable pgvector extension
    enable_extension 'vector'

    # ===== Lists =====
    # Note: pgvector 'vector' type is fixed at 1536 dimensions
    add_column :lists, :embedding, :vector unless column_exists?(:lists, :embedding)
    add_column :lists, :embedding_generated_at, :datetime unless column_exists?(:lists, :embedding_generated_at)
    add_column :lists, :requires_embedding_update, :boolean, default: false unless column_exists?(:lists, :requires_embedding_update)

    # ===== ListItems =====
    add_column :list_items, :embedding, :vector unless column_exists?(:list_items, :embedding)
    add_column :list_items, :embedding_generated_at, :datetime unless column_exists?(:list_items, :embedding_generated_at)
    add_column :list_items, :requires_embedding_update, :boolean, default: false unless column_exists?(:list_items, :requires_embedding_update)

    # ===== Comments =====
    add_column :comments, :embedding, :vector unless column_exists?(:comments, :embedding)
    add_column :comments, :embedding_generated_at, :datetime unless column_exists?(:comments, :embedding_generated_at)
    add_column :comments, :requires_embedding_update, :boolean, default: false unless column_exists?(:comments, :requires_embedding_update)

    # ===== Tags (from acts-as-taggable-on gem) =====
    # Note: Tags table already exists from the gem, we just add embedding support
    add_column :tags, :embedding, :vector unless column_exists?(:tags, :embedding)
    add_column :tags, :embedding_generated_at, :datetime unless column_exists?(:tags, :embedding_generated_at)
    add_column :tags, :requires_embedding_update, :boolean, default: false unless column_exists?(:tags, :requires_embedding_update)

    # Note: IVFFLAT indexes will be created separately in a post-migration task
    # This is because pgvector indexes have specific requirements that need
    # to be created after the pgvector extension is fully initialized
  end
end
