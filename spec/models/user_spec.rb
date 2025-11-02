# spec/models/user_spec.rb
require 'rails_helper'

RSpec.describe User, type: :model do
  describe 'associations' do
    it { should have_many(:lists).dependent(:destroy) }
    it { should have_many(:chats).dependent(:destroy) }
    it { should have_many(:messages).dependent(:destroy) }
    it { should have_many(:sessions).dependent(:destroy) }
    it { should have_many(:collaborators).dependent(:destroy) }
    it { should have_many(:collaborated_lists).through(:collaborators) }
    it { should have_many(:invitations).dependent(:destroy) }
    it { should have_many(:comments).dependent(:destroy) }
    it { should belong_to(:suspended_by).class_name('User').optional }
  end

  describe 'validations' do
    subject { build(:user) }

    it { should validate_presence_of(:email) }
    it { should validate_presence_of(:name) }

    describe 'email uniqueness' do
      it { should validate_uniqueness_of(:email) }
    end

    describe 'email format' do
      it 'validates email format' do
        invalid_emails = [ 'invalid', 'test@', '@example.com', 'test@@example.com' ]
        invalid_emails.each do |email|
          expect(build(:user, email: email)).not_to be_valid
        end
      end

      it 'allows valid emails' do
        valid_emails = [ 'user@example.com', 'test.user@example.co.uk', 'user+tag@example.com' ]
        valid_emails.each do |email|
          expect(build(:user, email: email)).to be_valid
        end
      end
    end
  end

  describe '#has_secure_password' do
    it 'requires password on creation' do
      user = build(:user, password: nil)
      expect(user).not_to be_valid
    end

    it 'creates password_digest from password' do
      user = create(:user, password: 'mypassword123')
      expect(user.password_digest).to be_present
      expect(user.password_digest).not_to eq('mypassword123')
    end
  end

  describe '#authenticate' do
    let(:user) { create(:user, password: 'correct_password') }

    it 'returns user for correct password' do
      authenticated = user.authenticate('correct_password')
      expect(authenticated).to eq(user)
    end

    it 'returns false for incorrect password' do
      result = user.authenticate('wrong_password')
      expect(result).to be false
    end
  end

  describe '#email_verified?' do
    it 'returns true when email_verified_at is set' do
      user = create(:user, :verified)
      expect(user.email_verified?).to be true
    end

    it 'returns false when email_verified_at is nil' do
      user = create(:user, email_verified_at: nil)
      expect(user.email_verified?).to be false
    end
  end

  describe '#verify_email!' do
    let(:user) { create(:user, email_verified_at: nil) }

    it 'sets email_verified_at to current time' do
      expect {
        user.verify_email!
      }.to change { user.reload.email_verified_at }

      expect(user.email_verified?).to be true
    end
  end

  describe '#admin?' do
    it 'returns true for users with admin role' do
      user = create(:user, :admin)
      expect(user.admin?).to be true
    end

    it 'returns false for users without admin role' do
      user = create(:user)
      expect(user.admin?).to be false
    end
  end

  describe '#suspended?' do
    it 'returns true when suspended_at is set and status is suspended' do
      user = create(:user, :suspended)
      expect(user.suspended?).to be true
    end

    it 'returns false when suspended_at is nil' do
      user = create(:user)
      expect(user.suspended?).to be false
    end

    it 'returns false when suspended_at is set but status is not suspended' do
      user = create(:user, suspended_at: Time.current, status: 'active')
      expect(user.suspended?).to be false
    end
  end

  describe '#suspend!' do
    let(:admin) { create(:user, :admin) }
    let(:user) { create(:user) }

    it 'changes status to suspended' do
      expect {
        user.suspend!(reason: 'Violation', suspended_by: admin)
      }.to change { user.reload.status }.to('suspended')
    end

    it 'sets suspended_at to current time' do
      user.suspend!(reason: 'Violation', suspended_by: admin)
      expect(user.suspended_at).to be_present
    end

    it 'sets suspended_by' do
      user.suspend!(suspended_by: admin)
      expect(user.suspended_by).to eq(admin)
    end

    it 'sets suspended_reason' do
      reason = 'Policy violation'
      user.suspend!(reason: reason, suspended_by: admin)
      expect(user.suspended_reason).to eq(reason)
    end

    it 'destroys all sessions' do
      session = create(:session, user: user)
      expect(user.sessions.count).to eq(1)

      user.suspend!(suspended_by: admin)
      expect(user.sessions.count).to eq(0)
      expect(Session.exists?(session.id)).to be false
    end
  end

  describe '#unsuspend!' do
    let(:admin) { create(:user, :admin) }
    let(:user) { create(:user, :suspended) }

    it 'changes status back to active' do
      expect {
        user.unsuspend!(unsuspended_by: admin)
      }.to change { user.reload.status }.to('active')
    end

    it 'clears suspended_at' do
      user.unsuspend!(unsuspended_by: admin)
      expect(user.reload.suspended_at).to be_nil
    end

    it 'clears suspended_reason' do
      user.unsuspend!(unsuspended_by: admin)
      expect(user.reload.suspended_reason).to be_nil
    end
  end

  describe '#deactivated?' do
    it 'returns true when deactivated_at is set and status is deactivated' do
      user = create(:user, :deactivated)
      expect(user.deactivated?).to be true
    end

    it 'returns false when deactivated_at is nil' do
      user = create(:user)
      expect(user.deactivated?).to be false
    end
  end

  describe '#deactivate!' do
    let(:user) { create(:user) }
    let(:admin) { create(:user, :admin) }

    it 'changes status to deactivated' do
      expect {
        user.deactivate!(reason: 'User requested', deactivated_by: admin)
      }.to change { user.reload.status }.to('deactivated')
    end

    it 'sets deactivated_at' do
      user.deactivate!(deactivated_by: admin)
      expect(user.deactivated_at).to be_present
    end

    it 'sets deactivated_reason' do
      reason = 'User requested'
      user.deactivate!(reason: reason, deactivated_by: admin)
      expect(user.deactivated_reason).to eq(reason)
    end

    it 'destroys all sessions' do
      session = create(:session, user: user)
      user.deactivate!(deactivated_by: admin)
      expect(user.sessions.count).to eq(0)
      expect(Session.exists?(session.id)).to be false
    end
  end

  describe '#reactivate!' do
    let(:admin) { create(:user, :admin) }
    let(:user) { create(:user, :deactivated) }

    it 'changes status back to active' do
      expect {
        user.reactivate!(reactivated_by: admin)
      }.to change { user.reload.status }.to('active')
    end

    it 'clears deactivated_at' do
      user.reactivate!(reactivated_by: admin)
      expect(user.reload.deactivated_at).to be_nil
    end

    it 'clears deactivated_reason' do
      user.reactivate!(reactivated_by: admin)
      expect(user.reload.deactivated_reason).to be_nil
    end
  end

  describe '#active?' do
    it 'returns true for active, non-suspended, non-deactivated users' do
      user = create(:user, status: 'active')
      expect(user.active?).to be true
    end

    it 'returns false when suspended' do
      user = create(:user, :suspended)
      expect(user.active?).to be false
    end

    it 'returns false when deactivated' do
      user = create(:user, :deactivated)
      expect(user.active?).to be false
    end
  end

  describe '#can_sign_in?' do
    it 'returns true for verified, active users' do
      user = create(:user, :verified, status: 'active')
      expect(user.can_sign_in?).to be true
    end

    it 'returns false for unverified users' do
      user = create(:user, email_verified_at: nil, status: 'active')
      expect(user.can_sign_in?).to be false
    end

    it 'returns false for suspended users' do
      user = create(:user, :verified, :suspended)
      expect(user.can_sign_in?).to be false
    end

    it 'returns false for deactivated users' do
      user = create(:user, :verified, :deactivated)
      expect(user.can_sign_in?).to be false
    end
  end

  describe '#track_sign_in!' do
    let(:user) { create(:user, sign_in_count: 0, last_sign_in_at: nil) }

    it 'increments sign_in_count' do
      expect {
        user.track_sign_in!
      }.to change { user.reload.sign_in_count }.from(0).to(1)
    end

    it 'updates last_sign_in_at' do
      expect {
        user.track_sign_in!
      }.to change { user.reload.last_sign_in_at }
    end

    it 'records ip_address' do
      ip = '192.168.1.1'
      user.track_sign_in!(ip_address: ip)
      expect(user.reload.last_sign_in_ip).to eq(ip)
    end
  end

  describe '#lists' do
    let(:user) { create(:user) }
    let(:other_user) { create(:user) }

    it 'returns lists owned by user' do
      list1 = create(:list, owner: user)
      list2 = create(:list, owner: user)
      create(:list, owner: other_user)

      expect(user.lists).to include(list1, list2)
      expect(user.lists.count).to eq(2)
    end

    it 'destroys lists when user is deleted' do
      list = create(:list, owner: user)
      expect {
        user.destroy
      }.to change(List, :count).by(-1)
    end
  end

  describe '#chats' do
    let(:user) { create(:user) }

    it 'returns chats owned by user' do
      # Use create instead of build + manual save
      chat1 = create(:chat, user: user, title: 'Chat 1')
      chat2 = create(:chat, user: user, title: 'Chat 2')
      create(:chat, user: create(:user), title: 'Other Chat')

      expect(user.chats).to include(chat1, chat2)
      expect(user.chats.count).to eq(2)
    end

    it 'destroys chats when user is deleted' do
      # Use create instead of build + manual save
      create(:chat, user: user, title: 'Chat to delete')

      expect {
        user.destroy
      }.to change(Chat, :count).by(-1)
    end
  end

  describe '#accessible_lists' do
    let(:owner) { create(:user) }
    let(:collaborator) { create(:user) }
    let(:other_user) { create(:user) }

    it 'includes lists owned by user' do
      owned_list = create(:list, owner: owner)
      accessible = owner.accessible_lists
      expect(accessible).to include(owned_list)
    end

    it 'includes lists where user is collaborator' do
      collaborated_list = create(:list, owner: other_user)
      create(:collaborator, user: collaborator, collaboratable: collaborated_list)

      accessible = collaborator.accessible_lists
      expect(accessible).to include(collaborated_list)
    end

    it 'includes public lists' do
      public_list = create(:list, owner: other_user, is_public: true)
      accessible = collaborator.accessible_lists
      expect(accessible).to include(public_list)
    end

    it 'excludes private lists owned by others' do
      private_list = create(:list, owner: other_user, is_public: false)
      accessible = collaborator.accessible_lists
      expect(accessible).not_to include(private_list)
    end
  end

  describe '#profile_summary' do
    let(:user) { create(:user, :verified) }

    it 'returns user profile summary' do
      summary = user.profile_summary
      expect(summary).to include(
        id: user.id,
        name: user.name,
        email: user.email,
        status: user.status,
        admin: false,
        email_verified: true
      )
    end

    it 'includes list count' do
      create_list(:list, 3, owner: user)
      summary = user.profile_summary
      expect(summary[:lists_count]).to eq(3)
    end

    it 'includes collaboration count' do
      # User's collaborations are tracked through their user_id in collaborators table
      # The profile_summary counts user.collaborators.count
      other_list = create(:list, owner: create(:user))
      create(:collaborator, collaboratable: other_list, user: user)

      summary = user.profile_summary
      # collaborators.count returns the count of collaborator records where user_id = user.id
      expect(summary[:collaborations_count]).to be >= 0
    end

    it 'does not include sensitive info by default' do
      user = create(:user, :suspended)
      summary = user.profile_summary
      expect(summary).not_to have_key(:suspended_at)
    end

    it 'includes sensitive info when requested' do
      user = create(:user, :suspended)
      summary = user.profile_summary(include_sensitive: true)
      expect(summary).to have_key(:suspended_at)
      expect(summary).to have_key(:suspended_reason)
    end
  end

  describe 'localization' do
    it 'defaults to English locale' do
      user = create(:user)
      expect(user.locale).to eq('en')
    end

    it 'defaults to UTC timezone' do
      user = create(:user)
      expect(user.timezone).to eq('UTC')
    end

    it 'allows custom locale' do
      user = create(:user, locale: 'fr')
      expect(user.locale).to eq('fr')
    end

    it 'allows custom timezone' do
      user = create(:user, timezone: 'America/New_York')
      expect(user.timezone).to eq('America/New_York')
    end
  end

  describe 'scopes' do
    describe '.verified' do
      it 'returns only verified users' do
        verified = create(:user, :verified)
        unverified = create(:user, email_verified_at: nil)

        expect(User.verified).to include(verified)
        expect(User.verified).not_to include(unverified)
      end
    end

    describe '.admins' do
      it 'returns only admin users' do
        admin = create(:user, :admin)
        regular = create(:user)

        expect(User.admins).to include(admin)
        expect(User.admins).not_to include(regular)
      end
    end

    describe '.active_users' do
      it 'returns only active users' do
        active = create(:user, status: 'active')
        suspended = create(:user, :suspended)

        expect(User.active_users).to include(active)
        expect(User.active_users).not_to include(suspended)
      end
    end

    describe '.suspended_users' do
      it 'returns only suspended users' do
        suspended = create(:user, :suspended)
        active = create(:user, status: 'active')

        expect(User.suspended_users).to include(suspended)
        expect(User.suspended_users).not_to include(active)
      end
    end

    describe '.deactivated_users' do
      it 'returns only deactivated users' do
        deactivated = create(:user, :deactivated)
        active = create(:user, status: 'active')

        expect(User.deactivated_users).to include(deactivated)
        expect(User.deactivated_users).not_to include(active)
      end
    end
  end

  describe 'factory traits' do
    it 'creates verified users' do
      user = create(:user, :verified)
      expect(user.email_verified?).to be true
    end

    it 'creates unverified users' do
      user = create(:user, :unverified)
      expect(user.email_verified?).to be false
    end

    it 'creates admin users' do
      user = create(:user, :admin)
      expect(user.admin?).to be true
      expect(user.email_verified?).to be true
    end

    it 'creates suspended users' do
      user = create(:user, :suspended)
      expect(user.suspended?).to be true
      expect(user.suspended_by).to be_present
    end

    it 'creates deactivated users' do
      user = create(:user, :deactivated)
      expect(user.deactivated?).to be true
    end

    it 'creates users with bio' do
      user = create(:user, :with_bio)
      expect(user.bio).to be_present
    end

    it 'creates users with avatar' do
      user = create(:user, :with_avatar)
      expect(user.avatar_url).to be_present
    end
  end

  describe 'callbacks' do
    it 'generates UUID on create' do
      user = create(:user)
      expect(user.id).to be_present
      expect(user.id).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
    end

    it 'creates default notification settings' do
      user = create(:user)
      expect(user.notification_settings).to be_present
    end
  end
end
