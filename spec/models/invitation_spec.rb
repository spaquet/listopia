# == Schema Information
#
# Table name: invitations
#
#  id                     :uuid             not null, primary key
#  email                  :string
#  granted_roles          :string           default([]), not null, is an Array
#  invitable_type         :string           not null
#  invitation_accepted_at :datetime
#  invitation_expires_at  :datetime
#  invitation_sent_at     :datetime
#  invitation_token       :string
#  message                :text
#  metadata               :jsonb            not null
#  permission             :integer          default("read"), not null
#  status                 :string           default("pending"), not null
#  created_at             :datetime         not null
#  updated_at             :datetime         not null
#  invitable_id           :uuid             not null
#  invited_by_id          :uuid
#  organization_id        :uuid
#  user_id                :uuid
#
# Indexes
#
#  index_invitations_on_email                (email)
#  index_invitations_on_invitable            (invitable_type,invitable_id)
#  index_invitations_on_invitable_and_email  (invitable_id,invitable_type,email) UNIQUE WHERE (email IS NOT NULL)
#  index_invitations_on_invitable_and_user   (invitable_id,invitable_type,user_id) UNIQUE WHERE (user_id IS NOT NULL)
#  index_invitations_on_invitation_token     (invitation_token) UNIQUE
#  index_invitations_on_invited_by_id        (invited_by_id)
#  index_invitations_on_organization_id      (organization_id)
#  index_invitations_on_status               (status)
#  index_invitations_on_user_id              (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (invited_by_id => users.id)
#  fk_rails_...  (user_id => users.id)
#
# spec/models/invitation_spec.rb
require 'rails_helper'

RSpec.describe Invitation, type: :model do
  describe 'associations' do
    it { should belong_to(:invitable) }
    it { should belong_to(:user).optional }
    it { should belong_to(:invited_by).class_name('User') }
  end

  describe 'validations' do
    let(:invitable) { create(:list) }
    let(:inviter) { create(:user) }

    it { should validate_presence_of(:permission) }

    describe 'email validation' do
      it 'validates email format when present' do
        invitation = build(:invitation, invitable: invitable, invited_by: inviter, email: 'invalid-email', user_id: nil)
        expect(invitation).not_to be_valid
        expect(invitation.errors[:email]).to be_present
      end

      it 'allows valid email format' do
        invitation = build(:invitation, invitable: invitable, invited_by: inviter, email: 'user@example.com')
        expect(invitation).to be_valid
      end

      it 'allows blank email when user_id is present' do
        user = create(:user)
        invitation = build(:invitation, invitable: invitable, invited_by: inviter, user: user, email: nil)
        expect(invitation).to be_valid
      end
    end

    describe 'email or user validation' do
      it 'validates email or user present' do
        invitation = build(:invitation, invitable: invitable, invited_by: inviter, email: nil, user_id: nil)
        expect(invitation).not_to be_valid
        expect(invitation.errors[:base]).to include('Either user or email must be present')
      end

      it 'allows invitation with user_id only' do
        user = create(:user)
        invitation = build(:invitation, invitable: invitable, invited_by: inviter, user: user, email: nil)
        expect(invitation).to be_valid
      end

      it 'allows invitation with email only' do
        invitation = build(:invitation, invitable: invitable, invited_by: inviter, email: 'newuser@example.com', user_id: nil)
        expect(invitation).to be_valid
      end
    end

    describe 'uniqueness validations' do
      let!(:existing_invitation) { create(:invitation, invitable: invitable, invited_by: inviter, email: 'existing@example.com') }

      it 'prevents duplicate invitations by email to same invitable' do
        invitation = build(:invitation, invitable: invitable, invited_by: inviter, email: 'existing@example.com')
        expect(invitation).not_to be_valid
        expect(invitation.errors[:email]).to be_present
      end

      it 'allows same email invited to different invitables' do
        other_list = create(:list)
        invitation = build(:invitation, invitable: other_list, invited_by: inviter, email: 'existing@example.com')
        expect(invitation).to be_valid
      end

      it 'prevents duplicate invitations by user_id to same invitable' do
        user = create(:user)
        create(:invitation, invitable: invitable, invited_by: inviter, user: user)
        invitation = build(:invitation, invitable: invitable, invited_by: inviter, user: user)
        expect(invitation).not_to be_valid
        expect(invitation.errors[:user_id]).to be_present
      end

      it 'allows same user invited to different invitables' do
        user = create(:user)
        create(:invitation, invitable: invitable, invited_by: inviter, user: user)
        other_list = create(:list)
        invitation = build(:invitation, invitable: other_list, invited_by: inviter, user: user)
        expect(invitation).to be_valid
      end
    end

    describe 'owner validation' do
      context 'when invitable is a List' do
        let(:list) { create(:list) }

        it 'prevents inviting the list owner by user' do
          invitation = build(:invitation, invitable: list, invited_by: create(:user), user: list.owner)
          expect(invitation).not_to be_valid
          expect(invitation.errors[:user]).to include('cannot be the list owner')
        end

        it 'prevents inviting the list owner by email' do
          invitation = build(:invitation, invitable: list, invited_by: create(:user), email: list.owner.email)
          expect(invitation).not_to be_valid
          expect(invitation.errors[:email]).to include('cannot be the list owner\'s email')
        end

        it 'allows inviting non-owner users' do
          other_user = create(:user)
          invitation = build(:invitation, invitable: list, invited_by: create(:user), user: other_user)
          expect(invitation).to be_valid
        end
      end
    end
  end

  describe 'enums' do
    let(:invitable) { create(:list) }
    let(:inviter) { create(:user) }

    describe 'permission enum' do
      it 'defines permission_read predicate' do
        invitation = create(:invitation, invitable: invitable, invited_by: inviter, permission: :read, email: 'test@example.com')
        expect(invitation).to be_permission_read
      end

      it 'defines permission_write predicate' do
        invitation = create(:invitation, invitable: invitable, invited_by: inviter, permission: :write, email: 'test@example.com')
        expect(invitation).to be_permission_write
      end

      it 'defaults to read permission' do
        invitation = create(:invitation, invitable: invitable, invited_by: inviter, email: 'test@example.com')
        expect(invitation).to be_permission_read
      end
    end
  end

  describe 'scopes' do
    let(:invitable) { create(:list) }
    let(:inviter) { create(:user) }
    let(:user) { create(:user) }

    describe '.pending' do
      let!(:pending_invitation) { create(:invitation, invitable: invitable, invited_by: inviter, user_id: nil, email: 'pending@example.com', status: 'pending') }
      let!(:accepted_invitation) { create(:invitation, invitable: invitable, invited_by: inviter, user: user, email: 'accepted@example.com', status: 'accepted') }

      it 'returns only pending invitations' do
        expect(Invitation.pending).to include(pending_invitation)
        expect(Invitation.pending).not_to include(accepted_invitation)
      end
    end

    describe '.accepted' do
      let!(:pending_invitation) { create(:invitation, invitable: invitable, invited_by: inviter, user_id: nil, email: 'pending@example.com', status: 'pending') }
      let!(:accepted_invitation) { create(:invitation, invitable: invitable, invited_by: inviter, user: user, email: 'accepted@example.com', status: 'accepted') }

      it 'returns only accepted invitations' do
        expect(Invitation.accepted).to include(accepted_invitation)
        expect(Invitation.accepted).not_to include(pending_invitation)
      end
    end
  end

  describe 'callbacks' do
    let(:invitable) { create(:list) }
    let(:inviter) { create(:user) }

    describe 'before_create' do
      it 'sets invitation_sent_at' do
        invitation = build(:invitation, invitable: invitable, invited_by: inviter, email: 'test@example.com')
        expect(invitation.invitation_sent_at).to be_nil
        invitation.save!
        expect(invitation.invitation_sent_at).to be_present
        expect(invitation.invitation_sent_at).to be_within(1.second).of(Time.current)
      end
    end
  end

  describe 'instance methods' do
    let(:invitable) { create(:list) }
    let(:inviter) { create(:user) }

    describe '#pending?' do
      it 'returns true when user_id is nil' do
        invitation = build(:invitation, invitable: invitable, invited_by: inviter, user_id: nil, email: 'test@example.com', status: 'pending')
        expect(invitation.pending?).to be true
      end

      it 'returns false when user_id is present' do
        user = create(:user)
        invitation = build(:invitation, invitable: invitable, invited_by: inviter, user: user, status: 'accepted')
        expect(invitation.pending?).to be false
      end
    end

    describe '#accepted?' do
      it 'returns false when user_id is nil' do
        invitation = build(:invitation, invitable: invitable, invited_by: inviter, user_id: nil, email: 'test@example.com', status: 'pending')
        expect(invitation.accepted?).to be false
      end

      it 'returns true when user_id is present' do
        user = create(:user)
        invitation = build(:invitation, invitable: invitable, invited_by: inviter, user: user, status: 'accepted')
        expect(invitation.accepted?).to be true
      end
    end

    describe '#display_email' do
      it 'returns user email when user is present' do
        user = create(:user, email: 'user@example.com')
        invitation = create(:invitation, invitable: invitable, invited_by: inviter, user: user, email: 'different@example.com')
        expect(invitation.display_email).to eq('user@example.com')
      end

      it 'returns invitation email when user is nil' do
        invitation = create(:invitation, invitable: invitable, invited_by: inviter, email: 'pending@example.com')
        expect(invitation.display_email).to eq('pending@example.com')
      end
    end

    describe '#display_name' do
      it 'returns user name when user is present' do
        user = create(:user, name: 'John Doe', email: 'john@example.com')
        invitation = create(:invitation, invitable: invitable, invited_by: inviter, user: user)
        expect(invitation.display_name).to eq('John Doe')
      end

      it 'returns invitation email when user is nil' do
        invitation = create(:invitation, invitable: invitable, invited_by: inviter, email: 'pending@example.com')
        expect(invitation.display_name).to eq('pending@example.com')
      end
    end

    describe '#accept!' do
      let(:accepting_user) { create(:user, email: 'accepter@example.com') }

      it 'returns false if email does not match' do
        invitation = create(:invitation, invitable: invitable, invited_by: inviter, email: 'different@example.com')
        result = invitation.accept!(accepting_user)
        expect(result).to be false
      end

      it 'creates a collaborator record with matching email' do
        invitation = create(:invitation, invitable: invitable, invited_by: inviter, email: accepting_user.email, permission: :write)
        expect {
          invitation.accept!(accepting_user)
        }.to change { invitable.collaborators.count }.by(1)
      end

      it 'sets the user on the invitation' do
        invitation = create(:invitation, invitable: invitable, invited_by: inviter, email: accepting_user.email)
        invitation.accept!(accepting_user)
        expect(invitation.user).to eq(accepting_user)
      end

      it 'sets invitation_accepted_at timestamp' do
        invitation = create(:invitation, invitable: invitable, invited_by: inviter, email: accepting_user.email)
        expect(invitation.invitation_accepted_at).to be_nil
        invitation.accept!(accepting_user)
        expect(invitation.invitation_accepted_at).to be_present
        expect(invitation.invitation_accepted_at).to be_within(1.second).of(Time.current)
      end

      it 'preserves the permission level' do
        invitation = create(:invitation, invitable: invitable, invited_by: inviter, email: accepting_user.email, permission: :write)
        collaborator = invitation.accept!(accepting_user)
        expect(collaborator.permission_write?).to be true
      end

      it 'returns the created collaborator' do
        invitation = create(:invitation, invitable: invitable, invited_by: inviter, email: accepting_user.email)
        collaborator = invitation.accept!(accepting_user)
        expect(collaborator).to be_a_kind_of(Collaborator)
        expect(collaborator.user).to eq(accepting_user)
      end
    end
  end

  describe 'class methods' do
    let(:invitable) { create(:list) }
    let(:inviter) { create(:user) }

    describe '.find_by_invitation_token' do
      it 'finds invitation by valid token' do
        invitation = create(:invitation, invitable: invitable, invited_by: inviter, email: 'test@example.com')
        token = invitation.generate_token_for(:invitation)
        found = Invitation.find_by_invitation_token(token)
        expect(found).to eq(invitation)
      end

      it 'returns nil for invalid token' do
        found = Invitation.find_by_invitation_token('invalid-token')
        expect(found).to be_nil
      end

      it 'returns nil for expired token' do
        invitation = create(:invitation, invitable: invitable, invited_by: inviter, email: 'test@example.com')
        token = invitation.generate_token_for(:invitation)

        Timecop.freeze(Time.current + 8.days) do
          found = Invitation.find_by_invitation_token(token)
          expect(found).to be_nil
        end
      end
    end
  end

  describe 'database' do
    let(:invitable) { create(:list) }
    let(:inviter) { create(:user) }

    it 'has UUID primary key' do
      invitation = create(:invitation, invitable: invitable, invited_by: inviter, email: 'test@example.com')
      expect(invitation.id).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/i)
    end

    it 'has timestamps' do
      invitation = create(:invitation, invitable: invitable, invited_by: inviter, email: 'test@example.com')
      expect(invitation.created_at).to be_present
      expect(invitation.updated_at).to be_present
    end
  end

  describe 'polymorphic invitable' do
    it 'can be associated with a List' do
      list = create(:list)
      inviter = create(:user)
      invitation = create(:invitation, invitable: list, invited_by: inviter, email: 'test@example.com')
      expect(invitation.invitable).to eq(list)
    end

    it 'stores invitable type' do
      list = create(:list)
      inviter = create(:user)
      invitation = create(:invitation, invitable: list, invited_by: inviter, email: 'test@example.com')
      expect(invitation.invitable_type).to eq('List')
    end
  end

  describe 'integration with Collaborator' do
    it 'creates correct permission when accepting invitation' do
      list = create(:list)
      inviter = create(:user)
      user = create(:user)
      invitation = create(:invitation, invitable: list, invited_by: inviter, email: user.email, permission: :read)

      collaborator = invitation.accept!(user)
      expect(collaborator.permission_read?).to be true
      expect(collaborator.user).to eq(user)
      expect(collaborator.collaboratable).to eq(list)
    end
  end
end
