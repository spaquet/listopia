# == Schema Information
#
# Table name: sessions
#
#  id               :uuid             not null, primary key
#  expires_at       :datetime         not null
#  ip_address       :string
#  last_accessed_at :datetime
#  session_token    :string           not null
#  user_agent       :string
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  user_id          :uuid             not null
#
# Indexes
#
#  index_sessions_on_expires_at              (expires_at)
#  index_sessions_on_session_token           (session_token) UNIQUE
#  index_sessions_on_user_id                 (user_id)
#  index_sessions_on_user_id_and_expires_at  (user_id,expires_at)
#
# Foreign Keys
#
#  fk_rails_...  (user_id => users.id)
#
# spec/models/session_spec.rb
require 'rails_helper'

RSpec.describe Session, type: :model do
  describe 'associations' do
    it { should belong_to(:user) }
  end

  describe 'validations' do
    let(:user) { create(:user) }

    it { should validate_presence_of(:session_token) }
    it { should validate_presence_of(:ip_address) }
    it { should validate_presence_of(:user_agent) }

    context 'with valid attributes' do
      it 'is valid' do
        session = build(:session, user: user)
        expect(session).to be_valid
      end
    end

    context 'without session_token' do
      it 'is invalid' do
        session = build(:session, user: user, session_token: nil)
        expect(session).not_to be_valid
      end
    end

    context 'without ip_address' do
      it 'is invalid' do
        session = build(:session, user: user, ip_address: nil)
        expect(session).not_to be_valid
      end
    end

    context 'without user_agent' do
      it 'is invalid' do
        session = build(:session, user: user, user_agent: nil)
        expect(session).not_to be_valid
      end
    end

    context 'with duplicate session_token' do
      it 'is invalid' do
        user1 = create(:user)
        user2 = create(:user)
        session1 = create(:session, user: user1)
        duplicate_session = build(:session, user: user2, session_token: session1.session_token)
        expect(duplicate_session).not_to be_valid
      end
    end

    describe 'session_token uniqueness' do
      let(:user) { create(:user) }

      it 'validates uniqueness of session_token' do
        session1 = create(:session, user: user)
        session2 = build(:session, user: user, session_token: session1.session_token)
        expect(session2).not_to be_valid
      end
    end
  end

  describe 'callbacks' do
    describe '#generate_session_token' do
      it 'generates a unique session_token' do
        session1 = create(:session)
        session2 = create(:session)

        expect(session1.session_token).to be_present
        expect(session2.session_token).to be_present
        expect(session1.session_token).not_to eq(session2.session_token)
      end

      it 'generates a URL-safe base64 token' do
        session = create(:session)
        # URL-safe base64 can only contain A-Z, a-z, 0-9, -, and _
        expect(session.session_token).to match(/\A[A-Za-z0-9\-_]+\z/)
      end

      it 'token is set before create' do
        session = build(:session)
        expect(session.session_token).to be_present
      end
    end

    describe '#set_expiry' do
      it 'sets expires_at in the future on create' do
        session = create(:session)
        expect(session.expires_at).to be > Time.current
      end

      it 'sets expires_at on factory creation' do
        session = create(:session)
        # Factory sets expires_at to 30.days.from_now
        expect(session.expires_at).to be_present
      end
    end
  end

  describe 'scopes' do
    describe '.active' do
      it 'returns sessions that have not expired' do
        active_session = create(:session, expires_at: 1.day.from_now)
        expired_session = create(:session, :expired)

        active_sessions = Session.active

        expect(active_sessions).to include(active_session)
        expect(active_sessions).not_to include(expired_session)
      end

      it 'returns sessions expiring in the future' do
        future_session = create(:session, expires_at: 29.days.from_now)
        expect(Session.active).to include(future_session)
      end

      it 'excludes sessions that expired exactly at current time' do
        # Create an expired session and set it to expire right now
        session = create(:session, :expired)
        session.update_column(:expires_at, Time.current)
        expect(Session.active).not_to include(session)
      end
    end

    describe '.expired' do
      it 'returns sessions that have expired' do
        active_session = create(:session, expires_at: 1.day.from_now)
        expired_session = create(:session, :expired)

        expired_sessions = Session.expired

        expect(expired_sessions).to include(expired_session)
        expect(expired_sessions).not_to include(active_session)
      end

      it 'returns sessions expiring at or before current time' do
        session = create(:session, :expired)
        session.update_column(:expires_at, Time.current)
        expect(Session.expired).to include(session)
      end
    end
  end

  describe '.find_by_token' do
    let(:user) { create(:user) }

    context 'with valid active token' do
      it 'returns the session' do
        session = create(:session, user: user, expires_at: 1.day.from_now)
        found_session = Session.find_by_token(session.session_token)

        expect(found_session).to eq(session)
      end
    end

    context 'with expired token' do
      it 'returns nil' do
        session = create(:session, :expired, user: user)
        found_session = Session.find_by_token(session.session_token)

        expect(found_session).to be_nil
      end
    end

    context 'with non-existent token' do
      it 'returns nil' do
        found_session = Session.find_by_token('nonexistent_token')
        expect(found_session).to be_nil
      end
    end

    context 'with multiple sessions for same user' do
      it 'returns the correct session by token' do
        session1 = create(:session, user: user, expires_at: 1.day.from_now)
        session2 = create(:session, user: user, expires_at: 1.day.from_now)

        found_session = Session.find_by_token(session1.session_token)
        expect(found_session).to eq(session1)
        expect(found_session).not_to eq(session2)
      end
    end
  end

  describe '#active?' do
    context 'when expires_at is in the future' do
      it 'returns true' do
        session = create(:session, expires_at: 1.day.from_now)
        expect(session.active?).to be true
      end
    end

    context 'when expires_at is in the past' do
      it 'returns false' do
        session = create(:session, :expired)
        expect(session.active?).to be false
      end
    end

    context 'when expires_at equals current time' do
      it 'returns false' do
        # Create a session that expired just now
        session = create(:session, :expired)
        # Set to exactly now (this is the boundary)
        session.update_column(:expires_at, Time.current)
        expect(session.active?).to be false
      end
    end

    context 'when expires_at is slightly in the future' do
      it 'returns true' do
        session = create(:session, expires_at: 1.second.from_now)
        expect(session.active?).to be true
      end
    end
  end

  describe '#extend_expiry!' do
    it 'extends the expiry by 30 days from now' do
      session = create(:session, expires_at: 1.day.from_now)
      original_expiry = session.expires_at

      session.extend_expiry!
      expected_expiry = 30.days.from_now
      expect(session.expires_at).to be_within(2.seconds).of(expected_expiry)
    end

    it 'persists the change to the database' do
      session = create(:session, expires_at: 1.day.from_now)
      session.extend_expiry!

      reloaded_session = Session.find(session.id)
      expect(reloaded_session.expires_at).to eq(session.expires_at)
    end

    it 'makes an expired session active again' do
      session = create(:session, :expired)
      expect(session.active?).to be false

      session.extend_expiry!
      expect(session.active?).to be true
    end

    it 'updates the updated_at timestamp' do
      session = create(:session)
      original_updated_at = session.updated_at

      Timecop.travel(1.second) do
        session.extend_expiry!
      end

      expect(session.updated_at).to be > original_updated_at
    end
  end

  describe '#revoke!' do
    it 'makes the session inactive' do
      session = create(:session, expires_at: 30.days.from_now)
      expect(session.active?).to be true

      session.revoke!
      expect(session.active?).to be false
    end

    it 'sets expires_at to current time or earlier' do
      session = create(:session, expires_at: 30.days.from_now)
      session.revoke!
      expect(session.expires_at).to be <= Time.current
    end

    it 'persists the change to the database' do
      session = create(:session)
      session.revoke!

      reloaded_session = Session.find(session.id)
      expect(reloaded_session.active?).to be false
    end

    it 'includes the session in the expired scope after revoke' do
      session = create(:session, expires_at: 30.days.from_now)
      session.revoke!

      expect(Session.expired).to include(session)
    end
  end

  describe 'user association' do
    it 'belongs to a user' do
      user = create(:user)
      session = create(:session, user: user)

      expect(session.user).to eq(user)
    end

    it 'destroys sessions when user is deleted' do
      user = create(:user)
      session = create(:session, user: user)
      session_id = session.id

      user.destroy

      expect { Session.find(session_id) }.to raise_error(ActiveRecord::RecordNotFound)
    end

    it 'maintains session integrity with correct user' do
      user1 = create(:user)
      user2 = create(:user)
      session1 = create(:session, user: user1)
      session2 = create(:session, user: user2)

      expect(session1.user_id).to eq(user1.id)
      expect(session2.user_id).to eq(user2.id)
    end
  end

  describe 'session attributes' do
    it 'stores ip_address' do
      session = create(:session, ip_address: '192.168.1.1')
      expect(session.ip_address).to eq('192.168.1.1')
    end

    it 'stores user_agent' do
      user_agent = 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
      session = create(:session, user_agent: user_agent)
      expect(session.user_agent).to eq(user_agent)
    end

    it 'stores last_accessed_at when provided' do
      last_accessed = 1.hour.ago
      session = create(:session, last_accessed_at: last_accessed)
      expect(session.last_accessed_at).to be_within(1.second).of(last_accessed)
    end

    it 'can have last_accessed_at updated' do
      session = create(:session)
      # Verify we can update it
      new_time = 5.minutes.ago
      session.update(last_accessed_at: new_time)
      expect(session.last_accessed_at).to be_within(1.second).of(new_time)
    end
  end

  describe 'timestamps' do
    it 'has created_at on creation' do
      session = create(:session)
      expect(session.created_at).not_to be_nil
      expect(session.created_at).to be_within(1.second).of(Time.current)
    end

    it 'has updated_at on creation' do
      session = create(:session)
      expect(session.updated_at).not_to be_nil
    end

    it 'updates updated_at when session is modified' do
      session = create(:session)
      original_updated_at = session.updated_at

      Timecop.travel(1.second) do
        session.update(last_accessed_at: Time.current)
      end

      expect(session.updated_at).to be > original_updated_at
    end
  end

  describe 'UUID primary key' do
    it 'generates UUID for id on creation' do
      session = create(:session)
      expect(session.id).to be_a(String)
      expect(session.id).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
    end

    it 'persists UUID correctly' do
      session = create(:session)
      reloaded_session = Session.find(session.id)
      expect(reloaded_session.id).to eq(session.id)
    end
  end
end
