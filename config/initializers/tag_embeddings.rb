# Initialize Tag embeddings support after acts-as-taggable-on is loaded
Rails.application.config.to_prepare do
  require Rails.root.join("app/models/acts_as_taggable_on/tag_extension")
end
