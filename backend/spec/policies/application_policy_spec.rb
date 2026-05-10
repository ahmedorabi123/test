require "rails_helper"

RSpec.describe ApplicationPolicy do
  let(:order)  { create(:order) }
  let(:admin)  { admin_user }
  let(:viewer) { viewer_user }

  it "raises if the user is nil" do
    expect { described_class.new(nil, order) }.to raise_error(Pundit::NotAuthorizedError)
  end

  it "admin passes any default action" do
    policy = described_class.new(admin, order)
    expect(policy.index?).to be true
    expect(policy.show?).to be true
    expect(policy.create?).to be true
    expect(policy.update?).to be true
    expect(policy.destroy?).to be true
    expect(policy.export?).to be true
    expect(policy.import?).to be true
    expect(policy.bulk?).to be true
  end

  it "denies a viewer with no permissions" do
    policy = described_class.new(viewer, order)
    expect(policy.index?).to be false
    expect(policy.create?).to be false
    expect(policy.destroy?).to be false
  end

  it "grants based on matching resource:action permission" do
    user = user_with_permissions("orders:read", "orders:write")
    policy = described_class.new(user, order)
    expect(policy.index?).to be true
    expect(policy.create?).to be true
    expect(policy.destroy?).to be false # no delete
  end

  describe "Scope" do
    it "returns the full scope by default" do
      create(:order)
      scope = described_class::Scope.new(admin, Order.all).resolve
      expect(scope.count).to eq(Order.count)
    end
  end
end
