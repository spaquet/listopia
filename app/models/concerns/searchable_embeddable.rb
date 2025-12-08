module SearchableEmbeddable
  extend ActiveSupport::Concern

  included do
    # Scopes for embedding management
    scope :needs_embedding, -> { where(requires_embedding_update: true).or(where(embedding: nil)) }
    scope :stale_embeddings, ->(hours = 720) {
      # Default: 30 days (720 hours)
      where("embedding_generated_at < ?", hours.hours.ago).or(where(embedding: nil))
    }

    # Mark embedding as stale on content changes
    before_save :mark_embedding_stale, if: :content_changed?

    # Schedule embedding generation after save
    after_commit :schedule_embedding_generation, on: [:create, :update]
  end

  class_methods do
    def semantic_search(query, user, limit: 10)
      SearchService.call(
        query: query,
        user: user,
        models: self,
        limit: limit
      )
    end
  end

  def embedding_stale?
    embedding.nil? || embedding_generated_at.nil? ||
      (Time.current - embedding_generated_at) > 30.days
  end

  def embedding_generated?
    embedding.present? && embedding_generated_at.present?
  end

  private

  def mark_embedding_stale
    self.requires_embedding_update = true
  end

  def schedule_embedding_generation
    return unless requires_embedding_update?
    return if Rails.env.test?

    EmbeddingGenerationJob.set(wait: 1.second).perform_later(self.class.name, id)
  end

  # Override in each model to specify which fields to embed
  def content_changed?
    false
  end

  # Override in each model to specify content for embedding
  def content_for_embedding
    ""
  end
end
