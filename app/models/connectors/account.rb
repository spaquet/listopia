module Connectors
  # == Schema Information
  #
  # Table name: connector_accounts
  #
  #  id                      :uuid             not null, primary key
  #  access_token_encrypted  :text
  #  display_name            :string
  #  email                   :string
  #  error_count             :integer          default(0), not null
  #  last_error              :text
  #  last_sync_at            :timestamptz
  #  metadata                :jsonb            not null
  #  provider                :string           not null
  #  provider_uid            :string           not null
  #  refresh_token_encrypted :text
  #  status                  :string           default("active"), not null
  #  token_expires_at        :timestamptz
  #  token_scope             :string
  #  created_at              :datetime         not null
  #  updated_at              :datetime         not null
  #  organization_id         :uuid             not null
  #  user_id                 :uuid             not null
  #
  # Indexes
  #
  #  idx_on_user_id_provider_provider_uid_1cce2a45f8  (user_id,provider,provider_uid) UNIQUE
  #  index_connector_accounts_on_created_at           (created_at)
  #  index_connector_accounts_on_organization_id      (organization_id)
  #  index_connector_accounts_on_provider             (provider)
  #  index_connector_accounts_on_status               (status)
  #  index_connector_accounts_on_user_id              (user_id)
  #
  # Foreign Keys
  #
  #  fk_rails_...  (organization_id => organizations.id)
  #  fk_rails_...  (user_id => users.id)
  #
  class Account < ApplicationRecord
    self.table_name = "connector_accounts"

    belongs_to :user
    belongs_to :organization
    has_many :settings, class_name: "Connectors::Setting", foreign_key: :connector_account_id, dependent: :destroy
    has_many :sync_logs, class_name: "Connectors::SyncLog", foreign_key: :connector_account_id, dependent: :destroy
    has_many :event_mappings, class_name: "Connectors::EventMapping", foreign_key: :connector_account_id, dependent: :destroy

    validates :user_id, :organization_id, :provider, :provider_uid, presence: true
    validates :provider_uid, uniqueness: { scope: [ :user_id, :provider ] }
    validates :status, inclusion: { in: %w[active paused revoked errored] }

    enum :status, { active: "active", paused: "paused", revoked: "revoked", errored: "errored" }

    scope :by_provider, ->(provider) { where(provider: provider) }
    scope :for_user, ->(user) { where(user_id: user.id) }
    scope :active_only, -> { where(status: :active) }
    scope :recent, -> { order(created_at: :desc) }

    def connected?
      active? && access_token.present?
    end

    def token_expired?
      return false if token_expires_at.blank?
      token_expires_at < Time.current
    end

    def access_token
      decrypt_token(access_token_encrypted)
    end

    def access_token=(token)
      self.access_token_encrypted = encrypt_token(token)
    end

    def refresh_token
      decrypt_token(refresh_token_encrypted)
    end

    def refresh_token=(token)
      self.refresh_token_encrypted = encrypt_token(token)
    end

    private

    def encryptor
      secret = Rails.application.credentials.dig(:connector_tokens, :secret)
      if secret.blank?
        # Generate a 32-byte key for aes-256-gcm in test/dev environments
        secret = Rails.application.key_generator.generate_key("connector_tokens.secret", 32)
      end
      ActiveSupport::MessageEncryptor.new(secret)
end

    def encrypt_token(token)
      return nil if token.blank?
      encryptor.encrypt_and_sign(token)
    end

    def decrypt_token(ciphertext)
      return nil if ciphertext.blank?
      encryptor.decrypt_and_verify(ciphertext)
    rescue ActiveSupport::MessageEncryptor::InvalidMessage
      nil
    end
  end
end
