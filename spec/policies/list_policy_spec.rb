require 'rails_helper'

RSpec.describe ListPolicy, type: :policy do
  let(:user1) { create(:user) }
  let(:user2) { create(:user) }
  let(:org1) { create(:organization, creator: user1) }
  let(:org2) { create(:organization, creator: user2) }

  before do
    # Setup memberships
    create(:organization_membership, organization: org1, user: user1, role: :owner)
    create(:organization_membership, organization: org2, user: user2, role: :owner)
  end


  describe "permissions .scope" do
    let(:list1) { create(:list, owner: user1, organization: org1) }
    let(:list2) { create(:list, owner: user2, organization: org2) }
    let(:personal_list1) { create(:list, owner: user1, organization: nil) }
    let(:personal_list2) { create(:list, owner: user2, organization: nil) }

    context "when user is member of org1" do
      it "returns lists owned by user in org1" do
        list1
        list2
        personal_list1
        personal_list2

        lists = Pundit.policy_scope(user1, List)
        expect(lists).to include(list1)
        expect(lists).not_to include(list2)
      end

      it "returns user's personal lists" do
        personal_list1
        personal_list2

        lists = Pundit.policy_scope(user1, List)
        expect(lists).to include(personal_list1)
        expect(lists).not_to include(personal_list2)
      end

      it "returns lists where user is a collaborator in org1" do
        list1_with_collab = create(:list, owner: user2, organization: org1)
        create(:organization_membership, organization: org1, user: user2, role: :member)
        create(:collaborator, collaboratable: list1_with_collab, user: user1, permission: :read)

        lists = Pundit.policy_scope(user1, List)
        expect(lists).to include(list1_with_collab)
      end

      it "excludes lists from other organizations" do
        list1
        list2

        lists = Pundit.policy_scope(user1, List)
        expect(lists).not_to include(list2)
      end

      it "excludes lists where user is not member or collaborator" do
        other_org_list = create(:list, owner: user2, organization: org2)

        lists = Pundit.policy_scope(user1, List)
        expect(lists).not_to include(other_org_list)
      end
    end

    context "when user is member of multiple orgs" do
      let(:org3) { create(:organization, creator: user1) }

      before do
        create(:organization_membership, organization: org3, user: user1, role: :member)
      end

      it "returns lists from all user's organizations" do
        list_org1 = create(:list, owner: user1, organization: org1)
        list_org3 = create(:list, owner: user1, organization: org3)
        personal = create(:list, owner: user1, organization: nil)

        lists = Pundit.policy_scope(user1, List)
        expect(lists).to include(list_org1, list_org3, personal)
      end
    end

    context "when user has suspended org membership" do
      it "excludes lists from suspended organization" do
        # Update the existing membership (created in before block) to suspended
        membership = OrganizationMembership.find_by(organization: org1, user: user1)
        membership.update!(status: :suspended)

        list1 = create(:list, owner: user1, organization: org1)

        lists = Pundit.policy_scope(user1, List)
        expect(lists).not_to include(list1)
      end
    end
  end

  describe "#show?" do
    context "with organization-scoped list" do
      let(:org_list) { create(:list, owner: user1, organization: org1) }

      context "user is member of the organization" do
        it "allows owner to view" do
          policy = described_class.new(user1, org_list)
          expect(policy.show?).to be_truthy
        end

        context "user is not owner" do
          it "allows collaborators to view" do
            create(:collaborator, collaboratable: org_list, user: user2)
            create(:organization_membership, organization: org1, user: user2, role: :member)

            policy = described_class.new(user2, org_list)
            expect(policy.show?).to be_truthy
          end

          it "denies non-collaborators" do
            create(:organization_membership, organization: org1, user: user2, role: :member)

            policy = described_class.new(user2, org_list)
            expect(policy.show?).to be_falsy
          end
        end
      end

      context "user is not member of the organization" do
        it "denies access to user from different organization" do
          policy = described_class.new(user2, org_list)
          expect(policy.show?).to be_falsy
        end

        it "denies access even if user is added as collaborator without org membership" do
          create(:collaborator, collaboratable: org_list, user: user2)

          policy = described_class.new(user2, org_list)
          expect(policy.show?).to be_falsy
        end
      end
    end

    context "with personal list" do
      let(:personal_list) { create(:list, owner: user1, organization: nil) }

      it "allows owner to view" do
        policy = described_class.new(user1, personal_list)
        expect(policy.show?).to be_truthy
      end

      it "allows collaborators to view" do
        create(:collaborator, collaboratable: personal_list, user: user2)

        policy = described_class.new(user2, personal_list)
        expect(policy.show?).to be_truthy
      end

      it "allows public lists to be viewed by anyone" do
        personal_list.update!(is_public: true)

        policy = described_class.new(user2, personal_list)
        expect(policy.show?).to be_truthy
      end

      it "denies non-collaborators from viewing private lists" do
        policy = described_class.new(user2, personal_list)
        expect(policy.show?).to be_falsy
      end
    end
  end

  describe "#create?" do
    it "allows any authenticated user to create lists" do
      new_list = build(:list, owner: user1)

      policy = described_class.new(user1, new_list)
      expect(policy.create?).to be_truthy
    end
  end

  describe "#update?" do
    context "with organization-scoped list" do
      let(:org_list) { create(:list, owner: user1, organization: org1) }

      context "user is not member of organization" do
        it "denies update" do
          policy = described_class.new(user2, org_list)
          expect(policy.update?).to be_falsy
        end
      end

      context "user is member of organization" do
        before { create(:organization_membership, organization: org1, user: user2, role: :member) }

        it "allows owner to update" do
          policy = described_class.new(user1, org_list)
          expect(policy.update?).to be_truthy
        end

        it "allows write collaborators to update" do
          create(:collaborator, collaboratable: org_list, user: user2, permission: :write)

          policy = described_class.new(user2, org_list)
          expect(policy.update?).to be_truthy
        end

        it "denies read collaborators from updating" do
          create(:collaborator, collaboratable: org_list, user: user2, permission: :read)

          policy = described_class.new(user2, org_list)
          expect(policy.update?).to be_falsy
        end

        it "denies non-collaborators from updating" do
          policy = described_class.new(user2, org_list)
          expect(policy.update?).to be_falsy
        end
      end
    end

    context "with personal list" do
      let(:personal_list) { create(:list, owner: user1, organization: nil) }

      it "allows owner to update" do
        policy = described_class.new(user1, personal_list)
        expect(policy.update?).to be_truthy
      end

      it "allows write collaborators to update" do
        create(:collaborator, collaboratable: personal_list, user: user2, permission: :write)

        policy = described_class.new(user2, personal_list)
        expect(policy.update?).to be_truthy
      end

      it "denies read collaborators from updating" do
        create(:collaborator, collaboratable: personal_list, user: user2, permission: :read)

        policy = described_class.new(user2, personal_list)
        expect(policy.update?).to be_falsy
      end

      it "denies non-collaborators from updating" do
        policy = described_class.new(user2, personal_list)
        expect(policy.update?).to be_falsy
      end
    end
  end

  describe "#destroy?" do
    context "with organization-scoped list" do
      let(:org_list) { create(:list, owner: user1, organization: org1) }

      context "user is not member of organization" do
        it "denies deletion" do
          policy = described_class.new(user2, org_list)
          expect(policy.destroy?).to be_falsy
        end
      end

      context "user is member of organization" do
        before { create(:organization_membership, organization: org1, user: user2, role: :member) }

        it "allows owner to delete" do
          policy = described_class.new(user1, org_list)
          expect(policy.destroy?).to be_truthy
        end

        it "denies collaborators from deleting" do
          create(:collaborator, collaboratable: org_list, user: user2, permission: :write)

          policy = described_class.new(user2, org_list)
          expect(policy.destroy?).to be_falsy
        end

        it "denies non-collaborators from deleting" do
          policy = described_class.new(user2, org_list)
          expect(policy.destroy?).to be_falsy
        end
      end
    end

    context "with personal list" do
      let(:personal_list) { create(:list, owner: user1, organization: nil) }

      it "allows owner to delete" do
        policy = described_class.new(user1, personal_list)
        expect(policy.destroy?).to be_truthy
      end

      it "denies collaborators from deleting" do
        create(:collaborator, collaboratable: personal_list, user: user2, permission: :write)

        policy = described_class.new(user2, personal_list)
        expect(policy.destroy?).to be_falsy
      end

      it "denies non-collaborators from deleting" do
        policy = described_class.new(user2, personal_list)
        expect(policy.destroy?).to be_falsy
      end
    end
  end

  describe "#share?" do
    context "with organization-scoped list" do
      let(:org_list) { create(:list, owner: user1, organization: org1) }

      context "user is not member of organization" do
        it "denies share" do
          policy = described_class.new(user2, org_list)
          expect(policy.share?).to be_falsy
        end
      end

      context "user is member of organization" do
        before { create(:organization_membership, organization: org1, user: user2, role: :member) }

        it "allows owner to share" do
          policy = described_class.new(user1, org_list)
          expect(policy.share?).to be_truthy
        end

        it "allows write collaborators to share" do
          create(:collaborator, collaboratable: org_list, user: user2, permission: :write)

          policy = described_class.new(user2, org_list)
          expect(policy.share?).to be_truthy
        end

        it "denies read collaborators from sharing" do
          create(:collaborator, collaboratable: org_list, user: user2, permission: :read)

          policy = described_class.new(user2, org_list)
          expect(policy.share?).to be_falsy
        end
      end
    end
  end

  describe "#toggle_public_access?" do
    context "with organization-scoped list" do
      let(:org_list) { create(:list, owner: user1, organization: org1) }

      context "user is not owner" do
        it "denies public access toggle" do
          create(:organization_membership, organization: org1, user: user2, role: :member)

          policy = described_class.new(user2, org_list)
          expect(policy.toggle_public_access?).to be_falsy
        end
      end

      context "user is owner" do
        it "allows public access toggle" do
          policy = described_class.new(user1, org_list)
          expect(policy.toggle_public_access?).to be_truthy
        end
      end
    end
  end

  describe "#manage_collaborators?" do
    context "with organization-scoped list" do
      let(:org_list) { create(:list, owner: user1, organization: org1) }

      context "user is not member of organization" do
        it "denies collaborator management" do
          policy = described_class.new(user2, org_list)
          expect(policy.manage_collaborators?).to be_falsy
        end
      end

      context "user is member of organization" do
        before { create(:organization_membership, organization: org1, user: user2, role: :member) }

        it "allows owner to manage collaborators" do
          policy = described_class.new(user1, org_list)
          expect(policy.manage_collaborators?).to be_truthy
        end

        it "denies non-owner collaborators from managing" do
          create(:collaborator, collaboratable: org_list, user: user2, permission: :write)

          policy = described_class.new(user2, org_list)
          expect(policy.manage_collaborators?).to be_falsy
        end
      end
    end
  end

  describe "organization boundary enforcement" do
    context "cross-organization access denial" do
      it "prevents user in org A from accessing list in org B" do
        org_a = create(:organization, creator: user1)
        org_b = create(:organization, creator: user2)

        create(:organization_membership, organization: org_a, user: user1, role: :owner)
        create(:organization_membership, organization: org_b, user: user2, role: :owner)

        list_in_b = create(:list, owner: user2, organization: org_b)

        policy = described_class.new(user1, list_in_b)
        expect(policy.show?).to be_falsy
      end

      it "prevents user from collaborating on list in organization they don't belong to" do
        org_b = create(:organization, creator: user2)
        create(:organization_membership, organization: org_b, user: user2, role: :owner)

        list_in_b = create(:list, owner: user2, organization: org_b)
        create(:collaborator, collaboratable: list_in_b, user: user1)

        policy = described_class.new(user1, list_in_b)
        expect(policy.show?).to be_falsy
      end
    end

    context "with suspended organization membership" do
      let(:org_list) { create(:list, owner: user1, organization: org1) }

      it "prevents access when membership is suspended" do
        member = create(:organization_membership, organization: org1, user: user2, role: :member)
        member.suspend!

        policy = described_class.new(user2, org_list)
        expect(policy.show?).to be_falsy
      end

      it "prevents access when membership is revoked" do
        member = create(:organization_membership, organization: org1, user: user2, role: :member)
        member.revoke!

        policy = described_class.new(user2, org_list)
        expect(policy.show?).to be_falsy
      end
    end
  end
end
