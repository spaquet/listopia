class EnableHstore < ActiveRecord::Migration[8.0]
  def change
    enable_extension :hstore unless extension_enabled?('hstore')
  end
end
