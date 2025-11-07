# spec/models/user_spec.rb
# == Schema Information
#
# Table name: users
#
#  id                       :uuid             not null, primary key
#  account_metadata         :jsonb
#  admin_notes              :text
#  avatar_url               :string
#  bio                      :text
#  deactivated_at           :datetime
#  deactivated_reason       :text
#  discarded_at             :datetime
#  email                    :string           not null
#  email_verification_token :string
#  email_verified_at        :datetime
#  invited_by_admin         :boolean          default(FALSE)
#  last_sign_in_at          :datetime
#  last_sign_in_ip          :string
#  locale                   :string(10)       default("en"), not null
#  name                     :string           not null
#  password_digest          :string           not null
#  provider                 :string
#  sign_in_count            :integer          default(0), not null
#  status                   :string           default("active"), not null
#  suspended_at             :datetime
#  suspended_reason         :text
#  timezone                 :string(50)       default("UTC"), not null
#  uid                      :string
#  created_at               :datetime         not null
#  updated_at               :datetime         not null
#  suspended_by_id          :uuid
#
# Indexes
#
#  index_users_on_account_metadata          (account_metadata) USING gin
#  index_users_on_deactivated_at            (deactivated_at)
#  index_users_on_discarded_at              (discarded_at)
#  index_users_on_email                     (email) UNIQUE
#  index_users_on_email_verification_token  (email_verification_token) UNIQUE
#  index_users_on_invited_by_admin          (invited_by_admin)
#  index_users_on_last_sign_in_at           (last_sign_in_at)
#  index_users_on_locale                    (locale)
#  index_users_on_provider_and_uid          (provider,uid) UNIQUE
#  index_users_on_status                    (status)
#  index_users_on_suspended_at              (suspended_at)
#  index_users_on_timezone                  (timezone)
#
# Foreign Keys
#
#  fk_rails_...  (suspended_by_id => users.id)
#
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

    it 'validates email uniqueness' do
      create(:user, email: 'taken@example.com')
      expect(build(:user, email: 'taken@example.com')).not_to be_valid
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

  describe '#make_admin!' do
    let(:user) { create(:user) }

    it 'adds admin role' do
      user.make_admin!
      expect(user.admin?).to be true
    end
  end

  describe '#remove_admin!' do
    let(:user) { create(:user, :admin) }

    it 'removes admin role' do
      user.remove_admin!
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

    it 'changes status to deactivated' do
      expect {
        user.deactivate!(reason: 'User request')
      }.to change { user.reload.status }.to('deactivated')
    end

    it 'sets deactivated_at' do
      user.deactivate!(reason: 'User request')
      expect(user.deactivated_at).to be_present
    end

    it 'sets deactivated_reason' do
      reason = 'Taking a break'
      user.deactivate!(reason: reason)
      expect(user.deactivated_reason).to eq(reason)
    end
  end

  describe '#active?' do
    it 'returns true for active, not suspended, not deactivated users' do
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
    it 'returns chats owned by user' do
      skip 'Chat model requires RubyLLM - tested in chat_spec.rb'
    end

    it 'destroys chats when user is deleted' do
      skip 'Chat model requires RubyLLM - tested in chat_spec.rb'
    end
  end

  describe '#current_chat' do
    it 'returns nil when no active chats' do
      skip 'Chat model requires RubyLLM - tested in chat_spec.rb'
    end

    it 'returns most recent active chat' do
      skip 'Chat model requires RubyLLM - tested in chat_spec.rb'
    end

    it 'ignores archived and completed chats' do
      skip 'Chat model requires RubyLLM - tested in chat_spec.rb'
    end
  end

  describe '#accessible_lists' do
    let(:user) { create(:user) }
    let(:other_user) { create(:user) }

    it 'includes lists owned by user' do
      owned_list = create(:list, owner: user)
      expect(user.accessible_lists).to include(owned_list)
    end

    it 'includes lists user collaborates on' do
      collaborated_list = create(:list, owner: other_user)
      create(:collaborator, collaboratable: collaborated_list, user: user)

      expect(user.accessible_lists).to include(collaborated_list)
    end

    it 'includes public lists' do
      public_list = create(:list, owner: other_user, is_public: true)
      expect(user.accessible_lists).to include(public_list)
    end

    it 'excludes private lists from other users' do
      private_list = create(:list, owner: other_user, is_public: false)
      expect(user.accessible_lists).not_to include(private_list)
    end
  end

  describe '.verified scope' do
    it 'returns only verified users' do
      verified = create(:user, :verified)
      unverified = create(:user, email_verified_at: nil)

      expect(User.verified).to include(verified)
      expect(User.verified).not_to include(unverified)
    end
  end

  describe '.admins scope' do
    it 'returns only admin users' do
      admin = create(:user, :admin)
      regular = create(:user)

      expect(User.admins).to include(admin)
      expect(User.admins).not_to include(regular)
    end
  end

  describe '.active_users scope' do
    it 'returns only active users' do
      active = create(:user, status: 'active')
      suspended = create(:user, :suspended)

      expect(User.active_users).to include(active)
      expect(User.active_users).not_to include(suspended)
    end
  end

  describe '.suspended_users scope' do
    it 'returns only suspended users' do
      suspended = create(:user, :suspended)
      active = create(:user, status: 'active')

      expect(User.suspended_users).to include(suspended)
      expect(User.suspended_users).not_to include(active)
    end
  end

  describe '.deactivated_users scope' do
    it 'returns only deactivated users' do
      deactivated = create(:user, :deactivated)
      active = create(:user, status: 'active')

      expect(User.deactivated_users).to include(deactivated)
      expect(User.deactivated_users).not_to include(active)
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

  describe 'enum :status' do
    it 'defines status_active? predicate' do
      user = create(:user, status: 'active')
      expect(user).to be_status_active
    end

    it 'defines status_suspended? predicate' do
      user = create(:user, :suspended)
      expect(user).to be_status_suspended
    end

    it 'defines status_deactivated? predicate' do
      user = create(:user, :deactivated)
      expect(user).to be_status_deactivated
    end
  end

  describe 'notification preferences' do
    let(:user) { create(:user) }

    it 'returns notification_settings or creates default' do
      settings = user.notification_preferences
      expect(settings).to be_present
      expect(settings).to be_a(NotificationSetting)
    end
  end

  describe 'password generation' do
    it 'generates different password_digest for each user' do
      user1 = create(:user, password: 'test123')
      user2 = create(:user, password: 'test123')

      expect(user1.password_digest).not_to eq(user2.password_digest)
    end
  end

  describe 'UUID primary key' do
    it 'generates UUID for id on creation' do
      user = create(:user)
      expect(user.id).to be_a(String)
      expect(user.id).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
    end

    it 'persists UUID correctly' do
      user = create(:user)
      reloaded_user = User.find(user.id)
      expect(reloaded_user.id).to eq(user.id)
    end
  end

  describe 'timestamps' do
    it 'has created_at on creation' do
      user = create(:user)
      expect(user.created_at).not_to be_nil
      expect(user.created_at).to be_within(1.second).of(Time.current)
    end

    it 'has updated_at on creation' do
      user = create(:user)
      expect(user.updated_at).not_to be_nil
    end

    it 'updates updated_at when user is modified' do
      user = create(:user)
      original_updated_at = user.updated_at

      sleep(0.1)
      user.update(name: 'Updated Name')

      expect(user.updated_at).to be > original_updated_at
    end
  end

  describe 'soft delete with discard' do
    it 'soft deletes user' do
      user = create(:user)
      user.discard

      expect(user).to be_discarded
    end

    it 'excludes discarded users from queries' do
      active_user = create(:user)
      discarded_user = create(:user)
      discarded_user.discard

      expect(User.kept).to include(active_user)
      expect(User.kept).not_to include(discarded_user)
    end
  end
end
