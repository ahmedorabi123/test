require "rails_helper"

RSpec.describe OrderPolicy do
  let(:order) { create(:order) }

  it "denies viewers" do
    p = described_class.new(viewer_user, order)
    expect(p.index?).to be false
    expect(p.cancel?).to be false
    expect(p.refund?).to be false
    expect(p.transition?).to be false
  end

  it "admins pass everything" do
    p = described_class.new(admin_user, order)
    expect(p.index?).to be true
    expect(p.cancel?).to be true
    expect(p.refund?).to be true
    expect(p.transition?).to be true
    expect(p.update?).to be true
    expect(p.export?).to be true
  end

  it "uses orders:cancel for cancel?" do
    user = user_with_permissions("orders:cancel")
    expect(described_class.new(user, order).cancel?).to be true
  end

  it "uses orders:refund for refund?" do
    user = user_with_permissions("orders:refund")
    expect(described_class.new(user, order).refund?).to be true
  end

  it "transition? accepts orders:write OR orders:update" do
    expect(described_class.new(user_with_permissions("orders:write"), order).transition?).to be true
    expect(described_class.new(user_with_permissions("orders:update"), order).transition?).to be true
    expect(described_class.new(viewer_user, order).transition?).to be false
  end

  it "export? requires orders:export" do
    expect(described_class.new(user_with_permissions("orders:export"), order).export?).to be true
    expect(described_class.new(viewer_user, order).export?).to be false
  end
end
