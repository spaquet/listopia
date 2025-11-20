# spec/models/team_spec.rb
# == Schema Information
#
# Table name: teams
#
#  id              :uuid             not null, primary key
#  metadata        :jsonb            not null
#  name            :string           not null
#  slug            :string           not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  created_by_id   :uuid             not null
#  organization_id :uuid             not null
#
# Indexes
#
#  index_teams_on_created_at                (created_at)
#  index_teams_on_created_by_id             (created_by_id)
#  index_teams_on_organization_id           (organization_id)
#  index_teams_on_organization_id_and_slug  (organization_id,slug) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (organization_id => organizations.id)
#
require 'rails_helper'

RSpec.describe Team, type: :model do
  let(:organization) { create(:organization) }
  let(:user) { create(:user) }
  let(:team) { create(:team, organization: organization, created_by: user) }

  describe 'associations' do
    it { is_expected.to belong_to(:organization) }
    it { is_expected.to belong_to(:creator).class_name('User').with_foreign_key('created_by_id') }
    it { is_expected.to have_many(:team_memberships).dependent(:destroy) }
    it { is_expected.to have_many(:users).through(:team_memberships) }
    it { is_expected.to have_many(:lists).dependent(:nullify) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_length_of(:name).is_at_least(1).is_at_most(255) }
    it { is_expected.to validate_presence_of(:slug) }
    it { is_expected.to validate_presence_of(:organization_id) }
    it { is_expected.to validate_presence_of(:created_by_id) }

    it 'validates slug uniqueness within organization' do
      create(:team, organization: organization, slug: 'test-team')
      duplicate = build(:team, organization: organization, slug: 'test-team')
      expect(duplicate).not_to be_valid
    end

    it 'allows same slug in different organizations' do
      other_org = create(:organization)
      create(:team, organization: organization, slug: 'test-team')
      same_slug = build(:team, organization: other_org, slug: 'test-team')
      expect(same_slug).to be_valid
    end

    it 'validates slug format' do
      team = build(:team, slug: 'Invalid Slug')
      expect(team).not_to be_valid
    end
  end

  describe '#generate_slug' do
    it 'generates slug from name' do
      team = build(:team, organization: organization, name: 'My Team', slug: '')
      team.validate
      expect(team.slug).to eq('my-team')
    end

    it 'generates unique slugs within organization' do
      create(:team, organization: organization, slug: 'test-team')
      team = build(:team, organization: organization, name: 'Test Team', slug: '')
      team.validate
      expect(team.slug).to eq('test-team-1')
    end
  end

  describe '#member?' do
    it 'returns true if user is a member' do
      team.team_memberships.create!(user: user, organization_membership_id: create(:organization_membership, organization: organization, user: user).id)
      expect(team.member?(user)).to be true
    end

    it 'returns false if user is not a member' do
      other_user = create(:user)
      expect(team.member?(other_user)).to be false
    end
  end

  describe '#user_role' do
    it 'returns the user role' do
      org_membership = create(:organization_membership, organization: organization, user: user)
      team.team_memberships.create!(user: user, organization_membership_id: org_membership.id, role: :admin)
      expect(team.user_role(user)).to eq('admin')
    end

    it 'returns nil if user is not a member' do
      other_user = create(:user)
      expect(team.user_role(other_user)).to be nil
    end
  end

  describe '#user_is_admin?' do
    it 'returns true for admin role' do
      org_membership = create(:organization_membership, organization: organization, user: user)
      team.team_memberships.create!(user: user, organization_membership_id: org_membership.id, role: :admin)
      expect(team.user_is_admin?(user)).to be true
    end

    it 'returns true for lead role' do
      org_membership = create(:organization_membership, organization: organization, user: user)
      team.team_memberships.create!(user: user, organization_membership_id: org_membership.id, role: :lead)
      expect(team.user_is_admin?(user)).to be true
    end

    it 'returns false for member role' do
      org_membership = create(:organization_membership, organization: organization, user: user)
      team.team_memberships.create!(user: user, organization_membership_id: org_membership.id, role: :member)
      expect(team.user_is_admin?(user)).to be false
    end
  end

  describe 'scopes' do
    describe '.by_organization' do
      it 'filters teams by organization' do
        org_team = create(:team, organization: organization)
        other_org = create(:organization)
        other_team = create(:team, organization: other_org)

        expect(Team.by_organization(organization)).to include(org_team)
        expect(Team.by_organization(organization)).not_to include(other_team)
      end
    end
  end
end
