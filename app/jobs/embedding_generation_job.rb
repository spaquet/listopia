class EmbeddingGenerationJob < ApplicationJob
  queue_as :default

  # Prevent duplicate embedding generation for the same record
  # Solid Queue uses a different concurrency model than GoodJob
  # We'll implement deduplication via a lock in the service instead

  def perform(model_name, record_id)
    model = model_name.constantize
    record = model.find(record_id)

    result = EmbeddingGenerationService.call(record)

    unless result.success?
      Rails.logger.error("Embedding generation failed for #{model_name} #{record_id}: #{result.errors.join(', ')}")

      # Optionally: re-enqueue with exponential backoff for retry
      # You can implement retry logic here if needed
    end
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn("Record not found for embedding: #{model_name} #{record_id}")
  rescue => e
    Rails.logger.error("Unexpected error in EmbeddingGenerationJob: #{e.class} - #{e.message}")
    raise
  end
end
