require 'rails_helper'

RSpec.describe User, type: :model do
  describe "validations" do
    it { is_expected.to validate_presence_of(:first_name) }
    it { is_expected.to validate_presence_of(:last_name) }
    it { is_expected.to validate_presence_of(:email) }
  end

  describe "#full_name" do
    it "joins first and last name" do
      user = build(:user, first_name: "Ada", last_name: "Lovelace")
      expect(user.full_name).to eq("Ada Lovelace")
    end
  end

  describe "#admin?" do
    it "returns true when user has admin role" do
      user = create(:user, :admin)
      expect(user.admin?).to be true
    end

    it "returns false for users without admin role" do
      user = create(:user)
      expect(user.admin?).to be false
    end
  end

  describe "#can?" do
    it "returns true when the user's role grants the permission" do
      perm = Permission.find_or_create_by!(resource: "orders", action: "read")
      role = Role.find_or_create_by!(name: "viewer_test")
      role.permissions << perm unless role.permissions.include?(perm)
      user = create(:user)
      user.roles << role

      expect(user.can?(:orders, :read)).to be true
      expect(user.can?(:orders, :write)).to be false
    end
  end

  describe ".active scope" do
    it "excludes inactive users" do
      active   = create(:user)
      inactive = create(:user, :inactive)
      expect(User.active).to include(active)
      expect(User.active).not_to include(inactive)
    end
  end
end
