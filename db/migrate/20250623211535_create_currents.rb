class CreateCurrents < ActiveRecord::Migration[8.0]
  def change
    create_table :currents do |t|
      t.timestamps
    end
  end
end
