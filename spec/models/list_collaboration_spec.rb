# spec/models/list_collaboration_spec.rb
require 'rails_helper'

RSpec.describe ListCollaboration, type: :model do
  let(:list) { create(:list) }
  let(:user) { create(:user, :verified) }
  let(:collaboration) { create(:list_collaboration, list: list, user: user) }

  describe 'validations' do
    subject { build(:list_collaboration) }

    it { should validate_presence_of(:permission) }

    context 'email or user presence validation' do
      it 'is valid with user and no email' do
        collaboration = build(:list_collaboration, user: user, email: nil)
        expect(collaboration).to be_valid
      end

      it 'is valid with email and no user (pending invitation)' do
        collaboration = build(:list_collaboration, :pending)
        expect(collaboration).to be_valid
      end

      it 'is invalid with neither user nor email' do
        collaboration = build(:list_collaboration, user: nil, email: nil)
        expect(collaboration).not_to be_valid
        expect(collaboration.errors[:base]).to include('Either user or email must be present')
      end
    end

    context 'email format validation' do
      it 'accepts valid email formats for pending invitations' do
        valid_emails = %w[
          user@example.com
          test.user@domain.co.uk
          user+tag@example.org
        ]

        valid_emails.each do |email|
          collaboration = build(:list_collaboration, :pending, email: email)
          expect(collaboration).to be_valid
        end
      end

      it 'rejects invalid email formats for pending invitations' do
        invalid_emails = %w[
          invalid_email
          @example.com
          user@
        ]

        invalid_emails.each do |email|
          collaboration = build(:list_collaboration, :pending, email: email)
          expect(collaboration).not_to be_valid
        end
      end

      it 'allows blank email when user is present' do
        collaboration = build(:list_collaboration, user: user, email: '')
        expect(collaboration).to be_valid
      end
    end

    context 'uniqueness validations' do
      let!(:existing_collaboration) { create(:list_collaboration, list: list, user: user) }

      it 'prevents duplicate user collaborations on same list' do
        duplicate = build(:list_collaboration, list: list, user: user)
        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:user_id]).to be_present
      end

      it 'prevents duplicate email invitations on same list' do
        pending = create(:list_collaboration, :pending, list: list, email: 'test@example.com')
        duplicate = build(:list_collaboration, :pending, list: list, email: 'test@example.com')

        expect(duplicate).not_to be_valid
        expect(duplicate.errors[:email]).to be_present
      end

      it 'allows same user on different lists' do
        other_list = create(:list)
        collaboration = build(:list_collaboration, list: other_list, user: user)
        expect(collaboration).to be_valid
      end
    end

    context 'list owner validation' do
      it 'prevents list owner from being added as collaborator by user_id' do
        owner = list.owner
        collaboration = build(:list_collaboration, list: list, user: owner)

        expect(collaboration).not_to be_valid
        expect(collaboration.errors[:user]).to include('cannot be the list owner')
      end

      it 'prevents list owner from being added as collaborator by email' do
        owner_email = list.owner.email
        collaboration = build(:list_collaboration, :pending, list: list, email: owner_email)

        expect(collaboration).not_to be_valid
        expect(collaboration.errors[:email]).to include("cannot be the list owner's email")
      end
    end

    context 'existing user validation' do
      let(:existing_user) { create(:user, :verified, email: 'existing@example.com') }

      before do
        create(:list_collaboration, list: list, user: existing_user)
      end

      it 'prevents email invitation to user who is already a collaborator' do
        collaboration = build(:list_collaboration, :pending, list: list, email: existing_user.email)

        expect(collaboration).not_to be_valid
        expect(collaboration.errors[:email]).to include('is already a collaborator on this list')
      end
    end
  end

  describe 'associations' do
    it { should belong_to(:list) }
    it { should belong_to(:user).optional }
  end

  describe 'enums' do
    it 'defines permission enum correctly' do
      expect(ListCollaboration.permissions).to eq({
        'read' => 0,
        'collaborate' => 1
      })
    end

    it 'allows setting permission using enum methods' do
      collaboration = create(:list_collaboration, :read_permission)
      expect(collaboration.permission_read?).to be true

      collaboration.permission_collaborate!
      expect(collaboration.permission_collaborate?).to be true
      expect(collaboration.permission_read?).to be false
    end
  end

  describe 'scopes' do
    let!(:pending_collaboration) { create(:list_collaboration, :pending, list: list) }
    let!(:accepted_collaboration) { create(:list_collaboration, :accepted, list: list) }
    let!(:read_collaboration) { create(:list_collaboration, :read_permission, list: list) }
    let!(:collaborate_collaboration) { create(:list_collaboration, :collaborate_permission, list: list) }

    describe '.pending' do
      it 'returns only pending collaborations' do
        expect(ListCollaboration.pending).to contain_exactly(pending_collaboration)
      end
    end

    describe '.accepted' do
      it 'returns only accepted collaborations' do
        accepted_items = ListCollaboration.accepted
        expect(accepted_items).to include(accepted_collaboration, read_collaboration, collaborate_collaboration)
        expect(accepted_items).not_to include(pending_collaboration)
      end
    end

    describe '.readers' do
      it 'returns only read permission collaborations' do
        expect(ListCollaboration.readers).to include(read_collaboration)
        expect(ListCollaboration.readers).not_to include(collaborate_collaboration)
      end
    end

    describe '.collaborators' do
      it 'returns only collaborate permission collaborations' do
        expect(ListCollaboration.collaborators).to include(collaborate_collaboration)
        expect(ListCollaboration.collaborators).not_to include(read_collaboration)
      end
    end
  end

  describe 'status methods' do
    describe '#pending?' do
      it 'returns true when user_id is nil' do
        pending = create(:list_collaboration, :pending)
        expect(pending.pending?).to be true
      end

      it 'returns false when user_id is present' do
        accepted = create(:list_collaboration, user: user)
        expect(accepted.pending?).to be false
      end
    end

    describe '#accepted?' do
      it 'returns true when user_id is present' do
        accepted = create(:list_collaboration, user: user)
        expect(accepted.accepted?).to be true
      end

      it 'returns false when user_id is nil' do
        pending = create(:list_collaboration, :pending)
        expect(pending.accepted?).to be false
      end
    end
  end

  describe 'display methods' do
    describe '#display_email' do
      it 'returns user email when user is present' do
        collaboration = create(:list_collaboration, user: user)
        expect(collaboration.display_email).to eq(user.email)
      end

      it 'returns stored email when user is nil' do
        collaboration = create(:list_collaboration, :pending, email: 'pending@example.com')
        expect(collaboration.display_email).to eq('pending@example.com')
      end
    end

    describe '#display_name' do
      it 'returns user name when user is present' do
        collaboration = create(:list_collaboration, user: user)
        expect(collaboration.display_name).to eq(user.name)
      end

      it 'returns user email when user is present but name is blank' do
        user_without_name = create(:user, name: '')
        collaboration = create(:list_collaboration, user: user_without_name)
        expect(collaboration.display_name).to eq(user_without_name.email)
      end

      it 'returns stored email when user is nil' do
        collaboration = create(:list_collaboration, :pending, email: 'pending@example.com')
        expect(collaboration.display_name).to eq('pending@example.com')
      end
    end
  end

  describe 'permission methods' do
    describe '#can_edit?' do
      it 'returns true for collaborate permission' do
        collaboration = create(:list_collaboration, :collaborate_permission)
        expect(collaboration.can_edit?).to be true
      end

      it 'returns false for read permission' do
        collaboration = create(:list_collaboration, :read_permission)
        expect(collaboration.can_edit?).to be false
      end
    end

    describe '#can_view?' do
      it 'returns true for all collaborations' do
        read_collab = create(:list_collaboration, :read_permission)
        write_collab = create(:list_collaboration, :collaborate_permission)

        expect(read_collab.can_view?).to be true
        expect(write_collab.can_view?).to be true
      end
    end
  end

  describe 'token generation and validation' do
    describe '#generate_invitation_token' do
      it 'generates a valid token' do
        collaboration = create(:list_collaboration, :pending)
        token = collaboration.generate_invitation_token

        expect(token).to be_present
        expect(token).to be_a(String)
      end

      it 'generates unique tokens' do
        collaboration = create(:list_collaboration, :pending)
        token1 = collaboration.generate_invitation_token
        token2 = collaboration.generate_invitation_token

        expect(token1).not_to eq(token2)
      end
    end

    describe '.find_by_invitation_token' do
      it 'finds collaboration with valid token' do
        collaboration = create(:list_collaboration, :pending)
        token = collaboration.generate_invitation_token

        found = ListCollaboration.find_by_invitation_token(token)
        expect(found).to eq(collaboration)
      end

      it 'returns nil for invalid token' do
        found = ListCollaboration.find_by_invitation_token('invalid_token')
        expect(found).to be_nil
      end

      it 'returns nil for expired token' do
        collaboration = create(:list_collaboration, :pending)
        token = collaboration.generate_invitation_token

        travel(25.hours) do  # Invitation tokens expire in 24 hours
          found = ListCollaboration.find_by_invitation_token(token)
          expect(found).to be_nil
        end
      end
    end
  end

  describe 'collaboration workflow' do
    context 'pending invitation' do
      let(:pending_collaboration) { create(:list_collaboration, :pending, email: 'invite@example.com') }

      it 'can be converted to accepted collaboration' do
        new_user = create(:user, :verified, email: 'invite@example.com')

        pending_collaboration.update!(user: new_user, email: nil)

        expect(pending_collaboration.reload.accepted?).to be true
        expect(pending_collaboration.user).to eq(new_user)
        expect(pending_collaboration.email).to be_nil
      end
    end

    context 'permission changes' do
      it 'can change from read to collaborate permission' do
        collaboration = create(:list_collaboration, :read_permission)

        collaboration.update!(permission: 'collaborate')

        expect(collaboration.permission_collaborate?).to be true
        expect(collaboration.can_edit?).to be true
      end

      it 'can change from collaborate to read permission' do
        collaboration = create(:list_collaboration, :collaborate_permission)

        collaboration.update!(permission: 'read')

        expect(collaboration.permission_read?).to be true
        expect(collaboration.can_edit?).to be false
      end
    end
  end

  describe 'edge cases and error handling' do
    it 'handles nil user gracefully in display methods' do
      collaboration = build(:list_collaboration, user: nil, email: 'test@example.com')

      expect(collaboration.display_email).to eq('test@example.com')
      expect(collaboration.display_name).to eq('test@example.com')
    end

    it 'handles blank email gracefully' do
      collaboration = build(:list_collaboration, user: user, email: '')

      expect(collaboration.display_email).to eq(user.email)
      expect(collaboration.display_name).to eq(user.name)
    end
  end

  describe 'UUID primary key' do
    it 'uses UUID as primary key' do
      expect(collaboration.id).to be_present
      expect(collaboration.id).to match(/\A[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\z/)
    end

    it 'generates unique UUIDs' do
      collab1 = create(:list_collaboration)
      collab2 = create(:list_collaboration)

      expect(collab1.id).not_to eq(collab2.id)
    end
  end

  describe 'factory traits' do
    it 'creates valid collaborations with all factory traits' do
      traits = [
        [ :read_permission ],
        [ :collaborate_permission ],
        [ :pending ],
        [ :accepted ]
      ]

      traits.each do |trait|
        expect(build(:list_collaboration, *trait)).to be_valid
      end
    end

    it 'creates pending collaborations correctly' do
      pending = create(:list_collaboration, :pending)

      expect(pending.user).to be_nil
      expect(pending.email).to be_present
      expect(pending.pending?).to be true
    end

    it 'creates accepted collaborations correctly' do
      accepted = create(:list_collaboration, :accepted)

      expect(accepted.user).to be_present
      expect(accepted.accepted?).to be true
      expect(accepted.invitation_accepted_at).to be_present
    end
  end

  describe 'complex validation scenarios' do
    let(:owner) { create(:user, :verified) }
    let(:list_with_owner) { create(:list, owner: owner) }

    it 'validates complex ownership scenarios' do
      # Try to add owner as collaborator - should fail
      collaboration = build(:list_collaboration, list: list_with_owner, user: owner)
      expect(collaboration).not_to be_valid

      # Try to invite owner by email - should fail
      collaboration = build(:list_collaboration, :pending, list: list_with_owner, email: owner.email)
      expect(collaboration).not_to be_valid

      # Add different user - should succeed
      other_user = create(:user, :verified)
      collaboration = build(:list_collaboration, list: list_with_owner, user: other_user)
      expect(collaboration).to be_valid
    end
  end
end
