class CreateChats < ActiveRecord::Migration[8.1]
  def change
    create_table :chats, id: :uuid do |t|
      t.timestamps
    end
  end
end
