class EmbeddingGenerationService < ApplicationService
  # Service for generating embeddings for searchable records using OpenAI's embedding API
  # Supports List, ListItem, Comment, and ActsAsTaggableOn::Tag models

  def initialize(record)
    @record = record
  end

  def call
    return failure(errors: [ "Record not found" ]) unless @record

    content = @record.content_for_embedding
    return failure(errors: [ "No content to embed" ]) if content.blank?

    Rails.logger.info("Generating embedding for #{@record.class.name} #{@record.id}")

    embedding_vector = fetch_embedding(content)
    return failure(errors: [ "Failed to generate embedding" ]) if embedding_vector.nil?

    @record.update_columns(
      embedding: embedding_vector,
      embedding_generated_at: Time.current,
      requires_embedding_update: false
    )

    Rails.logger.info("Successfully generated embedding for #{@record.class.name} #{@record.id}")
    success(data: @record)
  rescue StandardError => e
    Rails.logger.error("Embedding generation failed for #{@record.class.name} #{@record.id}: #{e.message}")
    failure(errors: [ e.message ], message: "Embedding generation failed")
  end

  private

  def fetch_embedding(text)
    # Truncate to safe token limit (3-small can handle ~8191 tokens, but we'll be conservative)
    truncated_text = text.truncate(8000)

    # Call OpenAI embedding API via ruby_llm
    response = RubyLLM::Embeddings.create(
      model: "text-embedding-3-small",
      input: truncated_text
    )

    return response.data.first.embedding if response.success?

    Rails.logger.error("OpenAI API error: #{response.inspect}")
    nil
  rescue => e
    Rails.logger.error("Error calling embedding API: #{e.class} - #{e.message}")
    nil
  end
end
