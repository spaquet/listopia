class CreateComments < ActiveRecord::Migration[8.0]
  def change
    create_table :comments, id: :uuid do |t|
      t.references :commentable, polymorphic: true, null: false, type: :uuid, index: true
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.text :content, null: false
      t.json :metadata, default: {}

      t.timestamps
    end
  end
end
