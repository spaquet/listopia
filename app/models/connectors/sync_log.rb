module Connectors
  # == Schema Information
  #
  # Table name: connector_sync_logs
  #
  #  id                     :uuid
  #  connector_account_id   :uuid
  #  operation              :string
  #  status                 :string
  #  records_processed      :integer
  #  records_created        :integer
  #  records_updated        :integer
  #  records_failed         :integer
  #  error_message          :text
  #  duration_ms            :integer
  #  started_at             :timestamptz
  #  completed_at           :timestamptz
  #  created_at             :timestamptz
  #  updated_at             :timestamptz
  #
  class SyncLog < ApplicationRecord
    self.table_name = "connector_sync_logs"

    belongs_to :account, class_name: "Connectors::Account"

    validates :operation, presence: true
    validates :status, presence: true, inclusion: { in: %w(pending in_progress success failure) }

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
