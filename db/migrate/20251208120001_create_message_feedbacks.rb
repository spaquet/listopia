class CreateMessageFeedbacks < ActiveRecord::Migration[8.1]
  def change
    create_table :message_feedbacks, id: :uuid do |t|
      t.uuid :message_id, null: false
      t.uuid :user_id, null: false
      t.uuid :chat_id, null: false
      t.integer :rating, null: false
      t.integer :feedback_type
      t.text :comment
      t.integer :helpfulness_score

      t.timestamps
    end

    add_index :message_feedbacks, [:message_id, :user_id], unique: true
    add_index :message_feedbacks, [:user_id, :created_at]
    add_index :message_feedbacks, :chat_id
    add_index :message_feedbacks, :rating

    add_foreign_key :message_feedbacks, :messages
    add_foreign_key :message_feedbacks, :users
    add_foreign_key :message_feedbacks, :chats
  end
end
