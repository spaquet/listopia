# db/migrate/20250623083440_enable_uuid_extension.rb
class EnableUuidExtension < ActiveRecord::Migration[8.0]
  def change
    enable_extension 'pgcrypto' unless extension_enabled?('pgcrypto')
  end
end
