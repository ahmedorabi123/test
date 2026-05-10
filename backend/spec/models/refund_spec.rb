require "rails_helper"

RSpec.describe Refund, type: :model do
  let(:order) { create(:order, total_price: 100) }

  describe "validations" do
    it "rejects negative amount" do
      r = build(:refund, order: order, amount: -1)
      expect(r).not_to be_valid
    end

    it "rejects unknown status" do
      r = build(:refund, order: order, status: "weird")
      expect(r).not_to be_valid
    end

    it "accepts each canonical status" do
      Refund::STATUSES.each do |s|
        r = build(:refund, order: order, status: s)
        expect(r).to be_valid, "expected #{s} to be valid"
      end
    end

    it "rejects unknown kind" do
      r = build(:refund, order: order, kind: "weird")
      expect(r).not_to be_valid
    end

    it "accepts each canonical kind" do
      Refund::KINDS.each do |k|
        expect(build(:refund, order: order, kind: k)).to be_valid
      end
    end
  end

  describe "#partial? / #full?" do
    it "is partial when 0 < amount < order.total_price" do
      r = build(:refund, order: order, amount: 25)
      expect(r.partial?).to be true
      expect(r.full?).to be false
    end

    it "is full when amount >= order.total_price" do
      r = build(:refund, order: order, amount: 100)
      expect(r.full?).to be true
      expect(r.partial?).to be false
    end

    it "is neither when amount is zero" do
      r = build(:refund, order: order, amount: 0)
      expect(r.partial?).to be false
      expect(r.full?).to be false
    end
  end

  describe "#shopify_linked?" do
    it "is true only when shopify_refund_id is set" do
      expect(build(:refund, shopify_refund_id: nil).shopify_linked?).to be false
      expect(build(:refund, shopify_refund_id: 1).shopify_linked?).to be true
    end
  end

  describe "scopes" do
    it ".with_restock" do
      restocked = create(:refund, order: order, restock: true)
      _other    = create(:refund, order: order, restock: false)
      expect(Refund.with_restock).to contain_exactly(restocked)
    end

    it ".manual_source filters out shopify-linked" do
      manual  = create(:refund, order: order, shopify_refund_id: nil)
      _from_s = create(:refund, order: order, shopify_refund_id: 5)
      expect(Refund.manual_source).to contain_exactly(manual)
    end
  end
end
