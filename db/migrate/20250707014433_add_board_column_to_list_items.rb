class AddBoardColumnToListItems < ActiveRecord::Migration[8.0]
  def change
    change_table :list_items do |t|
      t.references :board_column, type: :uuid, foreign_key: true
    end
  end
end
