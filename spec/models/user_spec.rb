require "rails_helper"

RSpec.describe User do
  def role_with(resource, action)
    role = Role.find_or_create_by!(name: "r-#{resource}-#{action}")
    role.add_permission(resource, action)
    role
  end

  describe "RBAC" do
    it "grants a permission only when a role provides it" do
      user = create(:user)
      user.roles << role_with("pricing", "publish")

      expect(user.has_permission?("pricing", "publish")).to be(true)
      expect(user.can?(:pricing, :publish)).to be(true)
      expect(user.cannot?(:pricing, :create)).to be(true)
    end

    it "assigns the viewer role by default on create" do
      Role.find_or_create_by!(name: "viewer")
      user = create(:user)
      expect(user.role_names).to include("viewer")
    end
  end

  describe "branch scoping" do
    it "treats a nil branch as global access to all branches" do
      b1 = create(:branch)
      b2 = create(:branch)
      admin = create(:user, branch: nil)

      expect(admin.all_branches?).to be(true)
      expect(admin.accessible_branch_ids).to include(b1.id, b2.id)
    end

    it "limits a branch-scoped user to their own branch" do
      branch = create(:branch)
      create(:branch) # another branch they should not see
      user = create(:user, branch: branch)

      expect(user.branch_scoped?).to be(true)
      expect(user.accessible_branch_ids).to eq([branch.id])
    end
  end
end
