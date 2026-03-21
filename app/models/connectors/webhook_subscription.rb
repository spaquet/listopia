# == Schema Information
#
# Table name: connector_webhook_subscriptions
#
#  id                   :uuid             not null, primary key
#  channel_token        :string
#  expires_at           :timestamptz
#  provider             :string           not null
#  status               :string           default("active")
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  calendar_id          :string           not null
#  connector_account_id :uuid             not null
#  resource_id          :string
#  subscription_id      :string           not null
#
# Indexes
#
#  idx_on_connector_account_id_status_517af4a019             (connector_account_id,status)
#  index_connector_webhook_subscriptions_on_expires_at       (expires_at)
#  index_connector_webhook_subscriptions_on_subscription_id  (subscription_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (connector_account_id => connector_accounts.id)
#
module Connectors
  class WebhookSubscription < ApplicationRecord
    self.table_name = "connector_webhook_subscriptions"

    belongs_to :connector_account, class_name: "Connectors::Account"

    enum :status, { active: "active", expired: "expired", revoked: "revoked" }, validate: true

    scope :expiring_soon, -> { active.where(expires_at: ..72.hours.from_now) }
    scope :for_provider, ->(provider) { where(provider: provider) }

    def expired?
      expires_at.present? && expires_at < Time.current
    end
  end
end
