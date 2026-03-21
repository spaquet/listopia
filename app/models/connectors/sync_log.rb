module Connectors
# == Schema Information
#
# Table name: connector_sync_logs
#
#  id                   :uuid             not null, primary key
#  completed_at         :timestamptz
#  duration_ms          :integer
#  error_message        :text
#  operation            :string           not null
#  records_created      :integer          default(0)
#  records_failed       :integer          default(0)
#  records_processed    :integer          default(0)
#  records_updated      :integer          default(0)
#  started_at           :timestamptz
#  status               :string           not null
#  created_at           :datetime         not null
#  updated_at           :datetime         not null
#  connector_account_id :uuid             not null
#
# Indexes
#
#  index_connector_sync_logs_on_connector_account_id  (connector_account_id)
#  index_connector_sync_logs_on_created_at            (created_at)
#  index_connector_sync_logs_on_operation             (operation)
#  index_connector_sync_logs_on_status                (status)
#
# Foreign Keys
#
#  fk_rails_...  (connector_account_id => connector_accounts.id)
#
  class SyncLog < ApplicationRecord
    self.table_name = "connector_sync_logs"

    belongs_to :connector_account, class_name: "Connectors::Account", foreign_key: :connector_account_id

    validates :operation, presence: true
    validates :status, presence: true, inclusion: { in: %w[pending in_progress success failure] }

    enum :status, { pending: "pending", in_progress: "in_progress", success: "success", failure: "failure" }

    scope :by_operation, ->(operation) { where(operation: operation) }
    scope :by_status, ->(status) { where(status: status) }
    scope :recent, -> { order(created_at: :desc) }
    scope :with_errors, -> { where(status: :failure) }

    def duration
      return nil unless started_at && completed_at
      ((completed_at - started_at) * 1000).to_i
    end
  end
end
