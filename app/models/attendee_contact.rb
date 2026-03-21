# == Schema Information
#
# Table name: attendee_contacts
#
#  id                :uuid             not null, primary key
#  avatar_url        :string
#  bio               :text
#  clearbit_data     :jsonb
#  company           :string
#  display_name      :string
#  email             :string           not null
#  enriched_at       :datetime
#  enrichment_status :string           default("pending")
#  github_data       :jsonb
#  github_username   :string
#  linkedin_data     :jsonb
#  linkedin_url      :string
#  location          :string
#  title             :string
#  twitter_url       :string
#  website_url       :string
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  organization_id   :uuid             not null
#  user_id           :uuid
#
# Indexes
#
#  idx_on_organization_id_enrichment_status_172943d07b   (organization_id,enrichment_status)
#  index_attendee_contacts_on_enriched_at                (enriched_at)
#  index_attendee_contacts_on_enrichment_status          (enrichment_status)
#  index_attendee_contacts_on_organization_id_and_email  (organization_id,email) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (organization_id => organizations.id)
#  fk_rails_...  (user_id => users.id) ON DELETE => nullify
#
class AttendeeContact < ApplicationRecord
  belongs_to :organization
  belongs_to :user, optional: true

  enum :enrichment_status, {
    pending: "pending",
    enriched: "enriched",
    partial: "partial",
    failed: "failed"
  }, validate: true

  scope :for_org, ->(org) { where(organization_id: org.id) }
  scope :needing_enrichment, -> { where(enrichment_status: ["pending", "failed"]).where("enriched_at IS NULL OR enriched_at < ?", 7.days.ago) }

  # Best available name
  def name
    display_name.presence || email.split("@").first
  end

  # True if this attendee is a registered app user
  def internal?
    user_id.present?
  end

  # Merge enrichment from Clearbit — preserves existing data
  def apply_clearbit(data)
    self.clearbit_data = data
    self.title ||= data.dig("employment", "title")
    self.company ||= data.dig("employment", "name")
    self.location ||= data.dig("geo", "city")
    self.avatar_url ||= data["avatar"]
    self.bio ||= data["bio"]
    if data.dig("twitter", "handle").present?
      self.twitter_url ||= "https://twitter.com/#{data['twitter']['handle']}"
    end
    self.github_username ||= data.dig("github", "handle")
    if data.dig("linkedin", "handle").present?
      self.linkedin_url ||= "https://linkedin.com/in/#{data['linkedin']['handle']}"
    end
  end

  # Merge enrichment from GitHub — preserves existing data
  def apply_github(data)
    self.github_data = data
    self.github_username ||= data["login"]
    self.avatar_url ||= data["avatar_url"]
    self.bio ||= data["bio"]
    self.website_url ||= data["blog"]
    self.location ||= data["location"]
    self.display_name ||= data["name"]
  end
end
