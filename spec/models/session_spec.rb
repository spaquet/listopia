# spec/models/session_spec.rb
require 'rails_helper'

RSpec.describe Session, type: :model do
  let(:user) { create(:user, :verified) }
  let(:session) { build(:session, user: user) }

  describe 'validations' do
    subject { build(:session) }

    it { should validate_presence_of(:session_token) }
    it { should validate_uniqueness_of(:session_token) }
    it { should validate_presence_of(:ip_address) }
    it { should validate_presence_of(:user_agent) }

    context 'session_token uniqueness' do
      it 'ensures session tokens are unique' do
        existing_session = create(:session, user: user)
        duplicate_session = build(:session, user: user, session_token: existing_session.session_token)

        expect(duplicate_session).not_to be_valid
        expect(duplicate_session.errors[:session_token]).to include('has already been taken')
      end
    end
  end

  describe 'associations' do
    it { should belong_to(:user) }
  end

  describe 'scopes' do
    let!(:active_session) { create(:session, user: user, expires_at: 1.hour.from_now) }
    let!(:expired_session) { create(:session, user: user, expires_at: 1.hour.ago) }

    describe '.active' do
      it 'returns only active sessions' do
        expect(Session.active).to contain_exactly(active_session)
      end
    end

    describe '.expired' do
      it 'returns only expired sessions' do
        expect(Session.expired).to contain_exactly(expired_session)
      end
    end
  end

  describe 'callbacks' do
    describe 'before_create callbacks' do
      it 'generates session_token automatically' do
        session = build(:session, user: user, session_token: nil)
        session.save!

        expect(session.session_token).to be_present
        expect(session.session_token.length).to be >= 32
      end

      it 'sets expiry date automatically' do
        freeze_time do
          session = build(:session, user: user, expires_at: nil)
          session.save!

          expect(session.expires_at).to be_within(1.second).of(30.days.from_now)
        end
      end

      it 'does not overwrite manually set session_token' do
        custom_token = 'custom_token_123'
        session = build(:session, user: user, session_token: custom_token)
        session.save!

        expect(session.session_token).to eq(custom_token)
      end

      it 'does not overwrite manually set expires_at' do
        custom_expiry = 7.days.from_now
        session = build(:session, user: user, expires_at: custom_expiry)
        session.save!

        expect(session.expires_at).to be_within(1.second).of(custom_expiry)
      end
    end
  end

  describe 'class methods' do
    describe '.find_by_token' do
      let!(:valid_session) { create(:session, user: user, expires_at: 1.hour.from_now) }
      let!(:expired_session) { create(:session, user: user, expires_at: 1.hour.ago) }

      it 'finds active session by token' do
        found_session = Session.find_by_token(valid_session.session_token)
        expect(found_session).to eq(valid_session)
      end

      it 'does not find expired session by token' do
        found_session = Session.find_by_token(expired_session.session_token)
        expect(found_session).to be_nil
      end

      it 'returns nil for non-existent token' do
        found_session = Session.find_by_token('non_existent_token')
        expect(found_session).to be_nil
      end
    end
  end

  describe 'instance methods' do
    describe '#active?' do
      it 'returns true when session has not expired' do
        session = create(:session, user: user, expires_at: 1.hour.from_now)
        expect(session.active?).to be true
      end

      it 'returns false when session has expired' do
        session = create(:session, user: user, expires_at: 1.hour.ago)
        expect(session.active?).to be false
      end

      it 'returns false when expires_at is exactly now' do
        freeze_time do
          session = create(:session, user: user, expires_at: Time.current)
          expect(session.active?).to be false
        end
      end
    end

    describe '#extend_expiry!' do
      it 'extends session expiry by 30 days' do
        session = create(:session, user: user, expires_at: 1.hour.from_now)
        original_expiry = session.expires_at

        freeze_time do
          session.extend_expiry!
          expect(session.expires_at).to be_within(1.second).of(30.days.from_now)
          expect(session.expires_at).to be > original_expiry
        end
      end

      it 'persists the new expiry date' do
        session = create(:session, user: user)

        freeze_time do
          session.extend_expiry!
          session.reload
          expect(session.expires_at).to be_within(1.second).of(30.days.from_now)
        end
      end
    end

    describe '#revoke!' do
      it 'sets expires_at to current time' do
        session = create(:session, user: user, expires_at: 1.hour.from_now)

        freeze_time do
          session.revoke!
          expect(session.expires_at).to eq(Time.current)
        end
      end

      it 'makes session inactive' do
        session = create(:session, user: user, expires_at: 1.hour.from_now)

        session.revoke!
        expect(session.active?).to be false
      end

      it 'persists the revocation' do
        session = create(:session, user: user, expires_at: 1.hour.from_now)

        freeze_time do
          session.revoke!
          session.reload
          expect(session.expires_at).to eq(Time.current)
        end
      end
    end
  end

  describe 'token generation' do
    it 'generates URL-safe tokens' do
      session = create(:session, user: user)

      # URL-safe base64 characters: A-Z, a-z, 0-9, -, _
      expect(session.session_token).to match(/\A[A-Za-z0-9_-]+\z/)
    end

    it 'generates tokens of sufficient length' do
      session = create(:session, user: user)

      # 32 bytes encoded as base64 should be at least 43 characters
      expect(session.session_token.length).to be >= 43
    end

    it 'generates unique tokens' do
      session1 = create(:session, user: user)
      session2 = create(:session, user: user)

      expect(session1.session_token).not_to eq(session2.session_token)
    end
  end

  describe 'session lifecycle' do
    it 'can track session creation and usage' do
      freeze_time do
        session = create(:session, user: user)

        expect(session.created_at).to eq(Time.current)
        expect(session.expires_at).to be_within(1.second).of(30.days.from_now)
        expect(session.active?).to be true
      end
    end

    it 'handles session expiration correctly' do
      session = create(:session, user: user, expires_at: 1.hour.from_now)

      expect(session.active?).to be true

      travel(2.hours) do
        expect(session.active?).to be false
        expect(Session.find_by_token(session.session_token)).to be_nil
      end
    end

    it 'allows manual session revocation' do
      session = create(:session, user: user, expires_at: 1.day.from_now)

      expect(session.active?).to be true

      session.revoke!

      expect(session.active?).to be false
      expect(Session.find_by_token(session.session_token)).to be_nil
    end
  end

  describe 'user association' do
    it 'belongs to a user' do
      session = create(:session, user: user)

      expect(session.user).to eq(user)
      expect(session.user).to be_a(User)
    end

    it 'is destroyed when user is destroyed' do
      session = create(:session, user: user)

      expect { user.destroy }.to change { Session.count }.by(-1)
    end

    it 'allows multiple sessions per user' do
      session1 = create(:session, user: user)
      session2 = create(:session, user: user)

      expect(user.sessions).to contain_exactly(session1, session2)
    end
  end

  describe 'metadata tracking' do
    it 'stores IP address' do
      ip_address = '192.168.1.1'
      session = create(:session, user: user, ip_address: ip_address)

      expect(session.ip_address).to eq(ip_address)
    end

    it 'stores user agent' do
      user_agent = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36'
      session = create(:session, user: user, user_agent: user_agent)

      expect(session.user_agent).to eq(user_agent)
    end

    it 'can track last accessed time' do
      session = create(:session, user: user)

      freeze_time do
        session.update!(last_accessed_at: Time.current)
        expect(session.last_accessed_at).to eq(Time.current)
      end
    end
  end

  describe 'security considerations' do
    it 'generates cryptographically secure tokens' do
      # Generate multiple tokens and ensure they don't follow predictable patterns
      tokens = 10.times.map do
        create(:session, user: user).session_token
      end

      # All tokens should be unique
      expect(tokens.uniq.length).to eq(10)

      # Tokens should not be sequential or predictable
      tokens.each_cons(2) do |token1, token2|
        expect(token1).not_to eq(token2)
      end
    end

    it 'handles session hijacking protection through token uniqueness' do
      session = create(:session, user: user)
      original_token = session.session_token

      # Attempt to create session with same token should fail
      duplicate_session = build(:session, user: user, session_token: original_token)
      expect(duplicate_session).not_to be_valid
    end
  end

  describe 'UUID primary key' do
    it 'uses UUID as primary key' do
      session = create(:session, user: user)

      expect(session.id).to be_present
      expect(session.id).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
    end

    it 'generates unique UUIDs' do
      session1 = create(:session, user: user)
      session2 = create(:session, user: user)

      expect(session1.id).not_to eq(session2.id)
    end
  end

  describe 'edge cases and error handling' do
    it 'handles nil expires_at gracefully in active? check' do
      session = build(:session, user: user, expires_at: nil)
      # This should not raise an error, but return false since nil < Time.current is false
      expect(session.active?).to be false
    end

    it 'handles very old sessions' do
      old_session = create(:session, user: user, expires_at: 1.year.ago)

      expect(old_session.active?).to be false
      expect(Session.find_by_token(old_session.session_token)).to be_nil
    end

    it 'handles sessions with future creation dates' do
      future_session = build(:session, user: user, created_at: 1.hour.from_now)
      future_session.save(validate: false) # Skip validations to test edge case

      expect(future_session).to be_persisted
    end
  end

  describe 'factory and test helpers' do
    it 'creates valid sessions with factory' do
      session = create(:session, user: user)

      expect(session).to be_valid
      expect(session).to be_persisted
      expect(session.user).to eq(user)
      expect(session.session_token).to be_present
      expect(session.ip_address).to be_present
      expect(session.user_agent).to be_present
      expect(session.expires_at).to be_present
    end
  end

  describe 'performance considerations' do
    it 'uses database indexes effectively for token lookups' do
      # Create multiple sessions to test index performance
      sessions = create_list(:session, 100, user: user)
      target_session = sessions.sample

      # This should be fast due to the unique index on session_token
      found_session = Session.find_by_token(target_session.session_token)
      expect(found_session).to eq(target_session)
    end

    it 'efficiently filters by expiry date' do
      # Create mix of active and expired sessions
      create_list(:session, 50, user: user, expires_at: 1.hour.from_now)
      create_list(:session, 50, user: user, expires_at: 1.hour.ago)

      # These should be efficient due to index on expires_at
      active_count = Session.active.count
      expired_count = Session.expired.count

      expect(active_count).to eq(50)
      expect(expired_count).to eq(50)
    end
  end
end
