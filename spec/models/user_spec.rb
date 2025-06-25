# spec/models/user_spec.rb
require 'rails_helper'

RSpec.describe User, type: :model do
  let(:user) { create(:user) }

  describe 'validations' do
    subject { build(:user) }

    it { should validate_presence_of(:email) }
    it { should validate_presence_of(:name) }
    it { should validate_uniqueness_of(:email) }
    it { should allow_value('user@example.com').for(:email) }
    it { should_not allow_value('invalid_email').for(:email) }
    it { should have_secure_password }

    context 'email format validation' do
      it 'accepts valid email formats' do
        valid_emails = %w[
          user@example.com
          test.user@domain.co.uk
          user+tag@example.org
          user123@test-domain.com
        ]

        valid_emails.each do |email|
          expect(build(:user, email: email)).to be_valid
        end
      end

      it 'rejects invalid email formats' do
        invalid_emails = %w[
          invalid_email
          @example.com
          user@
          user.example.com
          user@.com
          user@domain.
        ]

        invalid_emails.each do |email|
          expect(build(:user, email: email)).not_to be_valid
        end
      end
    end
  end

  describe 'associations' do
    it { should have_many(:lists).dependent(:destroy) }
    it { should have_many(:list_collaborations).dependent(:destroy) }
    it { should have_many(:collaborated_lists).through(:list_collaborations).source(:list) }
    it { should have_many(:sessions).dependent(:destroy) }
  end

  describe 'scopes' do
    let!(:verified_user) { create(:user, :verified) }
    let!(:unverified_user) { create(:user, :unverified) }

    describe '.verified' do
      it 'returns only verified users' do
        expect(User.verified).to contain_exactly(verified_user)
      end
    end
  end

  describe 'email verification' do
    describe '#email_verified?' do
      it 'returns true when email_verified_at is present' do
        verified_user = create(:user, :verified)
        expect(verified_user.email_verified?).to be true
      end

      it 'returns false when email_verified_at is nil' do
        unverified_user = create(:user, :unverified)
        expect(unverified_user.email_verified?).to be false
      end
    end

    describe '#verify_email!' do
      it 'sets email_verified_at to current time' do
        user = create(:user, :unverified)

        travel_to Time.current do
          user.verify_email!
          expect(user.email_verified_at).to be_within(1.second).of(Time.current)
        end
      end

      it 'persists the verification status' do
        user = create(:user, :unverified)
        user.verify_email!

        expect(user.reload.email_verified?).to be true
      end
    end
  end

  describe 'token generation' do
    describe '#generate_magic_link_token' do
      it 'generates a valid token' do
        token = user.generate_magic_link_token

        expect(token).to be_present
        expect(token).to be_a(String)
      end

      it 'generates unique tokens' do
        token1 = user.generate_magic_link_token
        token2 = user.generate_magic_link_token

        expect(token1).not_to eq(token2)
      end
    end

    describe '#generate_email_verification_token' do
      it 'generates and saves verification token' do
        expect { user.generate_email_verification_token }.to change { user.email_verification_token }
        expect(user.email_verification_token).to be_present
      end

      it 'persists the token to database' do
        token = user.generate_email_verification_token
        expect(user.reload.email_verification_token).to eq(token)
      end
    end
  end

  describe 'token validation' do
    describe '.find_by_magic_link_token' do
      it 'finds user with valid token' do
        token = user.generate_magic_link_token
        found_user = User.find_by_magic_link_token(token)

        expect(found_user).to eq(user)
      end

      it 'returns nil for invalid token' do
        found_user = User.find_by_magic_link_token('invalid_token')
        expect(found_user).to be_nil
      end

      it 'returns nil for expired token' do
        token = user.generate_magic_link_token

        travel(16.minutes) do  # Magic links expire in 15 minutes
          found_user = User.find_by_magic_link_token(token)
          expect(found_user).to be_nil
        end
      end
    end

    describe '.find_by_email_verification_token' do
      it 'finds user with valid verification token' do
        token = user.generate_email_verification_token
        found_user = User.find_by_email_verification_token(token)

        expect(found_user).to eq(user)
      end

      it 'returns nil for invalid token' do
        found_user = User.find_by_email_verification_token('invalid_token')
        expect(found_user).to be_nil
      end

      it 'returns nil for expired token' do
        token = user.generate_email_verification_token

        travel(25.hours) do  # Email verification tokens expire in 24 hours
          found_user = User.find_by_email_verification_token(token)
          expect(found_user).to be_nil
        end
      end
    end
  end

  describe '#accessible_lists' do
    let(:owner) { create(:user, :verified) }
    let(:collaborator) { create(:user, :verified) }
    let!(:owned_list) { create(:list, owner: owner) }
    let!(:collaborated_list) { create(:list) }
    let!(:other_list) { create(:list) }

    before do
      create(:list_collaboration, list: collaborated_list, user: collaborator)
    end

    it 'returns lists owned by the user' do
      expect(owner.accessible_lists).to include(owned_list)
    end

    it 'returns lists where user is a collaborator' do
      expect(collaborator.accessible_lists).to include(collaborated_list)
    end

    it 'does not return lists where user has no access' do
      expect(collaborator.accessible_lists).not_to include(other_list)
      expect(owner.accessible_lists).not_to include(other_list)
    end

    it 'returns unique lists when user is both owner and collaborator' do
      create(:list_collaboration, list: owned_list, user: owner)

      accessible_lists = owner.accessible_lists
      expect(accessible_lists.count { |list| list.id == owned_list.id }).to eq(1)
    end
  end

  describe 'password security' do
    it 'encrypts password with bcrypt' do
      user = create(:user, password: 'secret123')
      expect(user.password_digest).to be_present
      expect(user.password_digest).not_to eq('secret123')
    end

    it 'authenticates with correct password' do
      user = create(:user, password: 'secret123')
      expect(user.authenticate('secret123')).to eq(user)
    end

    it 'fails authentication with incorrect password' do
      user = create(:user, password: 'secret123')
      expect(user.authenticate('wrong_password')).to be false
    end
  end

  describe 'UUID primary key' do
    it 'uses UUID as primary key' do
      expect(user.id).to be_present
      expect(user.id).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
    end

    it 'generates unique UUIDs' do
      user1 = create(:user)
      user2 = create(:user)

      expect(user1.id).not_to eq(user2.id)
    end
  end
end
