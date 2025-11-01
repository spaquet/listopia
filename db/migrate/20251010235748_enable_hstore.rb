class EnableHstore < ActiveRecord::Migration[8.0]
  def change
    enable_extension :hstore
  end
end
