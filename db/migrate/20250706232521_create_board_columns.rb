# db/migrate/20250706232521_create_board_columns.rb
class CreateBoardColumns < ActiveRecord::Migration[8.0]
  def change
    create_table :board_columns, id: :uuid do |t|
      t.references :list, type: :uuid, null: false, foreign_key: true
      t.string :name, null: false
      t.integer :position, default: 0, null: false
      t.json :metadata, default: {}

      t.timestamps
    end
  end
end
