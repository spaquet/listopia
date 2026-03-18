module Connectors
# == Schema Information
#
# Table name: connector_settings
#
#  id                   :uuid             not null, primary key
#  key                  :string           not null
#  value                :text
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  connector_account_id :uuid             not null
#
# Indexes
#
#  index_connector_settings_on_connector_account_id_and_key  (connector_account_id,key) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (connector_account_id => connector_accounts.id)
#
  class Setting < ApplicationRecord
    self.table_name = "connector_settings"

    belongs_to :account, class_name: "Connectors::Account", foreign_key: :connector_account_id

    validates :key, presence: true
    validates :connector_account_id, :key, uniqueness: true

    scope :by_key, ->(key) { where(key: key) }
  end
end
