class AddListopiaChatOrgSupport < ActiveRecord::Migration[8.1]
  def change
    # ===== RubyLLM Base Columns Missing from CreateChats =====
    # Add user_id to chats (required for user ownership)
    add_column :chats, :user_id, :uuid, null: false unless column_exists?(:chats, :user_id)
    add_foreign_key :chats, :users, column: :user_id unless foreign_key_exists?(:chats, :users)

    # Add basic columns for chat management
    add_column :chats, :title, :string, limit: 255 unless column_exists?(:chats, :title)
    add_column :chats, :context, :json, default: {} unless column_exists?(:chats, :context)
    add_column :chats, :status, :string, default: "active" unless column_exists?(:chats, :status)
    add_column :chats, :last_message_at, :datetime unless column_exists?(:chats, :last_message_at)
    add_column :chats, :metadata, :json, default: {} unless column_exists?(:chats, :metadata)
    add_column :chats, :model_id_string, :string unless column_exists?(:chats, :model_id_string)
    add_column :chats, :last_stable_at, :datetime unless column_exists?(:chats, :last_stable_at)

    # ===== RubyLLM Base Columns Missing from CreateMessages =====
    # Add user_id to messages (optional - assistant messages don't have a user)
    add_column :messages, :user_id, :uuid unless column_exists?(:messages, :user_id)
    add_foreign_key :messages, :users, column: :user_id unless foreign_key_exists?(:messages, :users)

    # Add message management columns
    add_column :messages, :message_type, :string, default: "text" unless column_exists?(:messages, :message_type)
    add_column :messages, :metadata, :json, default: {} unless column_exists?(:messages, :metadata)
    add_column :messages, :context_snapshot, :json, default: {} unless column_exists?(:messages, :context_snapshot)
    add_column :messages, :llm_provider, :string unless column_exists?(:messages, :llm_provider)
    add_column :messages, :llm_model, :string unless column_exists?(:messages, :llm_model)
    add_column :messages, :model_id_string, :string unless column_exists?(:messages, :model_id_string)
    add_column :messages, :tool_call_id, :string unless column_exists?(:messages, :tool_call_id)
    add_column :messages, :token_count, :integer unless column_exists?(:messages, :token_count)
    add_column :messages, :processing_time, :decimal, precision: 8, scale: 3 unless column_exists?(:messages, :processing_time)

    # ===== Listopia-Specific: Organization & Team Support =====
    # Add organization and team support to chats
    add_column :chats, :organization_id, :uuid unless column_exists?(:chats, :organization_id)
    add_foreign_key :chats, :organizations, column: :organization_id unless foreign_key_exists?(:chats, :organizations)

    add_column :chats, :team_id, :uuid unless column_exists?(:chats, :team_id)
    add_foreign_key :chats, :teams, column: :team_id unless foreign_key_exists?(:chats, :teams)

    add_column :chats, :visibility, :string, default: "private" unless column_exists?(:chats, :visibility)

    # Add organization support to messages
    add_column :messages, :organization_id, :uuid unless column_exists?(:messages, :organization_id)
    add_foreign_key :messages, :organizations, column: :organization_id unless foreign_key_exists?(:messages, :organizations)

    # ===== Indexes for Performance =====
    # Chat indexes
    add_index :chats, :user_id unless index_exists?(:chats, :user_id)
    add_index :chats, [ :user_id, :created_at ] unless index_exists?(:chats, [ :user_id, :created_at ])
    add_index :chats, [ :user_id, :status ] unless index_exists?(:chats, [ :user_id, :status ])
    add_index :chats, :status unless index_exists?(:chats, :status)
    add_index :chats, :last_message_at unless index_exists?(:chats, :last_message_at)
    add_index :chats, :last_stable_at unless index_exists?(:chats, :last_stable_at)

    # Organization/Team indexes
    add_index :chats, :organization_id unless index_exists?(:chats, :organization_id)
    add_index :chats, [ :organization_id, :user_id ] unless index_exists?(:chats, [ :organization_id, :user_id ])
    add_index :chats, [ :organization_id, :created_at ] unless index_exists?(:chats, [ :organization_id, :created_at ])
    add_index :chats, :team_id unless index_exists?(:chats, :team_id)
    add_index :chats, [ :team_id, :user_id ] unless index_exists?(:chats, [ :team_id, :user_id ])
    add_index :chats, :visibility unless index_exists?(:chats, :visibility)

    # Message indexes
    add_index :messages, :user_id unless index_exists?(:messages, :user_id)
    add_index :messages, [ :user_id, :created_at ] unless index_exists?(:messages, [ :user_id, :created_at ])
    add_index :messages, :message_type unless index_exists?(:messages, :message_type)
    add_index :messages, :llm_provider unless index_exists?(:messages, :llm_provider)
    add_index :messages, [ :llm_provider, :llm_model ] unless index_exists?(:messages, [ :llm_provider, :llm_model ])
    add_index :messages, :model_id_string unless index_exists?(:messages, :model_id_string)
    add_index :messages, :tool_call_id unless index_exists?(:messages, :tool_call_id)

    # Organization indexes
    add_index :messages, :organization_id unless index_exists?(:messages, :organization_id)
    add_index :messages, [ :organization_id, :user_id ] unless index_exists?(:messages, [ :organization_id, :user_id ])
  end
end
