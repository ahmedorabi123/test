require "rails_helper"

RSpec.describe Fulfillment, type: :model do
  let(:order) { create(:order) }

  describe "validations" do
    it "requires status be in STATUSES" do
      f = build(:fulfillment, order: order, status: "bogus")
      expect(f).not_to be_valid
      expect(f.errors[:status]).to be_present
    end

    it "accepts each canonical status" do
      Fulfillment::STATUSES.each do |s|
        f = build(:fulfillment, order: order, status: s)
        expect(f).to be_valid, "expected #{s} to be valid"
      end
    end
  end

  describe "tags coercion" do
    it "normalises a comma string into a unique array" do
      f = create(:fulfillment, order: order, tags: " a , b , a ")
      expect(f.tags).to eq(%w[a b])
    end

    it "normalises an array, stripping blanks" do
      f = create(:fulfillment, order: order, tags: [" x ", "", "y", "y"])
      expect(f.tags).to eq(%w[x y])
    end
  end

  describe "#bosta?" do
    it "is case-insensitive" do
      expect(build(:fulfillment, tracking_company: "Bosta").bosta?).to be true
      expect(build(:fulfillment, tracking_company: "BOSTA").bosta?).to be true
      expect(build(:fulfillment, tracking_company: "FedEx").bosta?).to be false
      expect(build(:fulfillment, tracking_company: nil).bosta?).to be false
    end
  end

  describe "#shopify_linked?" do
    it "returns true only when shopify_fulfillment_id is set" do
      expect(build(:fulfillment, shopify_fulfillment_id: nil).shopify_linked?).to be false
      expect(build(:fulfillment, shopify_fulfillment_id: 999).shopify_linked?).to be true
    end
  end

  describe "scopes" do
    it ".successful filters status=success" do
      success = create(:fulfillment, order: order, status: "success")
      _failed = create(:fulfillment, order: order, status: "failure")
      expect(Fulfillment.successful).to contain_exactly(success)
    end

    it ".via_bosta is case-insensitive" do
      bosta = create(:fulfillment, order: order, tracking_company: "BoStA")
      _other = create(:fulfillment, order: order, tracking_company: "DHL")
      expect(Fulfillment.via_bosta).to contain_exactly(bosta)
    end
  end

  describe "syncing last_delivery_status to order" do
    it "writes the latest fulfillment's delivery_status onto the order" do
      f1 = create(:fulfillment, order: order, delivery_status: "in_transit")
      expect(order.reload.last_delivery_status).to eq("in_transit")

      _f2 = create(:fulfillment, order: order, delivery_status: "delivered")
      expect(order.reload.last_delivery_status).to eq("delivered")

      f1.destroy
      expect(order.reload.last_delivery_status).to eq("delivered")
    end

    it "clears last_delivery_status when all fulfillments are destroyed" do
      f = create(:fulfillment, order: order, delivery_status: "delivered")
      f.destroy
      expect(order.reload.last_delivery_status).to be_nil
    end
  end
end
