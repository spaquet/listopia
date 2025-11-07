class AddRubyLlmV19Columns < ActiveRecord::Migration[8.1]
  def change
    unless column_exists?(:messages, :cached_tokens)
      add_column :messages, :cached_tokens, :integer
    end

    unless column_exists?(:messages, :cache_creation_tokens)
      add_column :messages, :cache_creation_tokens, :integer
    end

    unless column_exists?(:messages, :content_raw)
      add_column :messages, :content_raw, :json
    end
  end
end
