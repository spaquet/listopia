# Extension for ActsAsTaggableOn::Tag model to add embedding and search support
module ActsAsTaggableOn
  module TagExtension
    extend ActiveSupport::Concern

    included do
      include SearchableEmbeddable
      include PgSearch::Model

      # Full-text search scope
      pg_search_scope :search_by_keyword,
        against: { name: "A" },
        using: { tsearch: { prefix: true } }
    end

    def content_for_embedding
      name
    end

    private

    def content_changed?
      name_changed?
    end
  end
end

# Patch the ActsAsTaggableOn::Tag class
ActsAsTaggableOn::Tag.include(ActsAsTaggableOn::TagExtension)
