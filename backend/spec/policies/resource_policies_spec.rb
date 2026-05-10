require "rails_helper"

# Policies that delegate to ApplicationPolicy with a specific resource_name.
# These tests assert the resource gate is correct (so e.g. `products:write`
# can't open the orders door).
RSpec.describe "Resource-scoped policies" do
  let(:order)        { create(:order) }
  let(:warehouse)    { create(:warehouse) }
  let(:variant)      { create(:variant) }
  let(:stock_item)   { create(:stock_item, variant: variant, warehouse: warehouse) }

  describe RefundPolicy do
    it "uses orders resource" do
      user = user_with_permissions("orders:refund", "orders:read")
      expect(described_class.new(user, order).index?).to be true
      expect(described_class.new(user_with_permissions("products:read"), order).index?).to be false
    end
  end

  describe FulfillmentPolicy do
    it "is read-only via orders resource" do
      user = user_with_permissions("orders:read")
      expect(described_class.new(user, order).index?).to be true
      expect(described_class.new(user, order).create?).to be false
    end
  end

  describe StockItemPolicy do
    it "uses stock_items resource" do
      reader = user_with_permissions("stock_items:read")
      writer = user_with_permissions("stock_items:write")
      expect(described_class.new(reader, stock_item).index?).to be true
      expect(described_class.new(reader, stock_item).update?).to be false
      expect(described_class.new(writer, stock_item).update?).to be true
    end
  end

  describe WarehousePolicy do
    it "uses warehouses resource" do
      user = user_with_permissions("warehouses:read")
      expect(described_class.new(user, warehouse).index?).to be true
      expect(described_class.new(user, warehouse).create?).to be false
    end
  end

  describe ProductPolicy do
    it "uses products resource" do
      user = user_with_permissions("products:write")
      expect(described_class.new(user, Product).create?).to be true
    end
  end

  describe CustomerPolicy do
    it "uses customers resource" do
      user = user_with_permissions("customers:read")
      expect(described_class.new(user, Customer.new).index?).to be true
    end
  end

  describe PurchaseOrderPolicy do
    let(:po_class) { defined?(PurchaseOrder) ? PurchaseOrder : Class.new }

    it "grants receive? on purchase_orders:receive" do
      user = user_with_permissions("purchase_orders:receive")
      expect(described_class.new(user, po_class).receive?).to be true
    end

    it "grants approve? on purchase_orders:approve" do
      user = user_with_permissions("purchase_orders:approve")
      expect(described_class.new(user, po_class).approve?).to be true
    end

    it "purchase_orders:write also satisfies receive?/approve?" do
      user = user_with_permissions("purchase_orders:write")
      expect(described_class.new(user, po_class).receive?).to be true
      expect(described_class.new(user, po_class).approve?).to be true
    end
  end
end

RSpec.describe UserPolicy do
  let(:admin) { admin_user }
  let(:other) { create(:user) }

  it "admin sees all" do
    expect(described_class.new(admin, other).index?).to be true
    expect(described_class.new(admin, other).create?).to be true
    expect(described_class.new(admin, other).update?).to be true
  end

  it "non-admin sees only self" do
    me = create(:user)
    expect(described_class.new(me, other).index?).to be false
    expect(described_class.new(me, me).show?).to be true
    expect(described_class.new(me, other).show?).to be false
    expect(described_class.new(me, me).update?).to be true
  end

  it "admin cannot delete self" do
    expect(described_class.new(admin, admin).destroy?).to be false
    expect(described_class.new(admin, other).destroy?).to be true
  end

  describe "Scope" do
    it "admin sees all users; others see only themselves" do
      me = create(:user)
      _another = create(:user)
      expect(described_class::Scope.new(admin, User.all).resolve.count).to eq(User.count)
      expect(described_class::Scope.new(me, User.all).resolve.pluck(:id)).to eq([me.id])
    end
  end
end

RSpec.describe RolePolicy do
  it "admin can create/update/destroy" do
    p = described_class.new(admin_user, Role.new)
    expect(p.create?).to be true
    expect(p.update?).to be true
    expect(p.destroy?).to be true
  end

  it "non-admin with roles:read can index but not write" do
    user = user_with_permissions("roles:read")
    p = described_class.new(user, Role.new)
    expect(p.index?).to be true
    expect(p.create?).to be false
    expect(p.update?).to be false
  end

  it "viewer cannot read roles" do
    expect(described_class.new(viewer_user, Role.new).index?).to be false
  end
end

RSpec.describe AuditLogPolicy do
  it "only admin can index" do
    expect(described_class.new(admin_user, AuditLog).index?).to be true
    expect(described_class.new(viewer_user, AuditLog).index?).to be false
    expect(described_class.new(user_with_permissions("settings:read"), AuditLog).index?).to be false
  end
end
