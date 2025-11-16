# spec/models/organization_spec.rb
require 'rails_helper'

RSpec.describe Organization, type: :model do
  let(:user) { create(:user) }
  let(:organization) { create(:organization, created_by: user) }

  describe 'associations' do
    it { is_expected.to belong_to(:creator).class_name('User').with_foreign_key('created_by_id') }
    it { is_expected.to have_many(:organization_memberships).dependent(:destroy) }
    it { is_expected.to have_many(:users).through(:organization_memberships) }
    it { is_expected.to have_many(:teams).dependent(:destroy) }
    it { is_expected.to have_many(:lists).dependent(:destroy) }
    it { is_expected.to have_many(:invitations).dependent(:destroy) }
  end

  describe 'validations' do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_length_of(:name).is_at_least(1).is_at_most(255) }
    it { is_expected.to validate_presence_of(:slug) }
    it { is_expected.to validate_uniqueness_of(:slug) }
    it { is_expected.to validate_presence_of(:created_by_id) }
    it { is_expected.to validate_presence_of(:status) }

    it 'validates slug format' do
      org = build(:organization, slug: 'Invalid Slug')
      org.valid?
      expect(org.errors[:slug]).to be_present
    end

    it 'accepts valid slug formats' do
      org = build(:organization, slug: 'valid-slug-123')
      expect(org).to be_valid
    end
  end

  describe 'enums' do
    it { is_expected.to define_enum_for(:size).with_values(small: 0, medium: 1, large: 2, enterprise: 3) }
    it { is_expected.to define_enum_for(:status).with_values(active: 0, suspended: 1, deleted: 2) }
  end

  describe '#generate_slug' do
    it 'generates a slug from name' do
      org = build(:organization, name: 'My Organization', slug: '')
      org.validate
      expect(org.slug).to eq('my-organization')
    end

    it 'generates unique slugs' do
      create(:organization, slug: 'test-org')
      org = build(:organization, name: 'Test Org', slug: '')
      org.validate
      expect(org.slug).to eq('test-org-1')
    end

    it 'does not override existing slug' do
      org = build(:organization, slug: 'custom-slug')
      org.validate
      expect(org.slug).to eq('custom-slug')
    end
  end

  describe '#member?' do
    it 'returns true if user is a member' do
      organization.organization_memberships.create!(user: user, role: :member)
      expect(organization.member?(user)).to be true
    end

    it 'returns false if user is not a member' do
      other_user = create(:user)
      expect(organization.member?(other_user)).to be false
    end
  end

  describe '#user_role' do
    it 'returns the user role' do
      organization.organization_memberships.create!(user: user, role: :admin)
      expect(organization.user_role(user)).to eq('admin')
    end

    it 'returns nil if user is not a member' do
      other_user = create(:user)
      expect(organization.user_role(other_user)).to be nil
    end
  end

  describe '#user_has_role?' do
    it 'returns true if user has the specified role' do
      organization.organization_memberships.create!(user: user, role: :admin)
      expect(organization.user_has_role?(user, 'admin')).to be true
    end

    it 'returns false if user does not have the role' do
      organization.organization_memberships.create!(user: user, role: :member)
      expect(organization.user_has_role?(user, 'admin')).to be false
    end
  end

  describe '#user_is_admin?' do
    it 'returns true for admin role' do
      organization.organization_memberships.create!(user: user, role: :admin)
      expect(organization.user_is_admin?(user)).to be true
    end

    it 'returns true for owner role' do
      organization.organization_memberships.create!(user: user, role: :owner)
      expect(organization.user_is_admin?(user)).to be true
    end

    it 'returns false for member role' do
      organization.organization_memberships.create!(user: user, role: :member)
      expect(organization.user_is_admin?(user)).to be false
    end
  end

  describe '#user_is_owner?' do
    it 'returns true for owner role' do
      organization.organization_memberships.create!(user: user, role: :owner)
      expect(organization.user_is_owner?(user)).to be true
    end

    it 'returns false for other roles' do
      organization.organization_memberships.create!(user: user, role: :admin)
      expect(organization.user_is_owner?(user)).to be false
    end
  end

  describe 'scopes' do
    describe '.active' do
      it 'returns only active organizations' do
        active_org = create(:organization, status: :active)
        suspended_org = create(:organization, status: :suspended)
        expect(Organization.active).to include(active_org)
        expect(Organization.active).not_to include(suspended_org)
      end
    end
  end
end
