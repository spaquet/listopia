# 20250910233319_migrate_to_ruby_llm_model_references.rb

class MigrateToRubyLlmModelReferences < ActiveRecord::Migration[8.0]
  def up
    model_class = Model
    chat_class = Chat
    message_class = Message

    # Then check for any models in existing data that aren't in models.json
    say_with_time "Checking for additional models in existing data" do
      collect_and_create_models(chat_class, :chats, model_class)
      collect_and_create_models(message_class, :messages, model_class)
      model_class.count
    end

    # Migrate foreign keys
    migrate_foreign_key(:chats, chat_class, model_class, :model)
    migrate_foreign_key(:messages, message_class, model_class, :model)
  end

  def down
    # Remove foreign key references
    if column_exists?(:messages, :model_id)
      remove_reference :messages, :model, foreign_key: true
    end

    if column_exists?(:chats, :model_id)
      remove_reference :chats, :model, foreign_key: true
    end

    # Restore original model_id string columns
    if column_exists?(:messages, :model_id_string)
      rename_column :messages, :model_id_string, :model_id
    end

    if column_exists?(:chats, :model_id_string)
      rename_column :chats, :model_id_string, :model_id
    end
  end

  private

  def collect_and_create_models(record_class, table_name, model_class)
    return unless column_exists?(table_name, :model_id)

    has_provider = column_exists?(table_name, :provider)

    # Collect unique model/provider combinations using read_attribute to bypass overrides
    models_set = Set.new

    record_class.find_each do |record|
      model_id = record.read_attribute(:model_id)
      next if model_id.blank?

      provider = has_provider ? record.read_attribute(:provider) : nil
      models_set.add([ model_id, provider ])
    end

    models_set.each do |model_id, provider|
      find_or_create_model(model_id, provider, model_class)
    end
  end

  def find_or_create_model(model_id, provider, model_class)
    return if model_id.blank?

    begin
      model_info, _provider = RubyLLM.models.resolve(model_id, provider: provider)

      model_class.find_or_create_by!(
        model_id: model_info.id,
        provider: model_info.provider
      ) do |m|
        m.name = model_info.name || model_info.id
        m.family = model_info.family
        m.model_created_at = model_info.created_at
        m.context_window = model_info.context_window
        m.max_output_tokens = model_info.max_output_tokens
        m.knowledge_cutoff = model_info.knowledge_cutoff
        m.modalities = model_info.modalities.to_h
        m.capabilities = model_info.capabilities
        m.pricing = model_info.pricing.to_h
        m.metadata = model_info.metadata
      end
    rescue => e
      # Skip models that can't be resolved - they'll need manual fixing
      Rails.logger.warn "Skipping unresolvable model: #{model_id} - will need manual update"
      nil
    end
  end


  def migrate_foreign_key(table_name, record_class, model_class, foreign_key_name)
    return unless column_exists?(table_name, :model_id)

    # Check if we need to rename the string column to avoid collision
    if column_exists?(table_name, :model_id) && !foreign_key_exists?(table_name, :models)
      # Temporarily rename the string column
      rename_column table_name, :model_id, :model_id_string
    end

    # Add the foreign key reference
    unless column_exists?(table_name, "#{foreign_key_name}_id")
      add_reference table_name, foreign_key_name, foreign_key: true
    end

    say_with_time "Migrating #{table_name} model references" do
      record_class.reset_column_information
      has_provider = column_exists?(table_name, :provider)

      # Determine which column to read from (renamed or original)
      model_id_column = column_exists?(table_name, :model_id_string) ? :model_id_string : :model_id

      record_class.find_each do |record|
        model_id = record.read_attribute(model_id_column)
        next if model_id.blank?

        provider = has_provider ? record.read_attribute(:provider) : nil

        model = if has_provider && provider.present?
          model_class.find_by(model_id: model_id, provider: provider)
        else
          find_model_for_record(model_id, model_class)
        end

        record.update_column("#{foreign_key_name}_id", model.id) if model
      end
    end
  end

  def find_model_for_record(model_id, model_class)
    begin
      model_info, _provider = RubyLLM.models.resolve(model_id)
      model_class.find_by(model_id: model_info.id, provider: model_info.provider)
    rescue => e
      model_class.find_by(model_id: model_id)
    end
  end
end
