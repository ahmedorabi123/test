require "rails_helper"

RSpec.describe Order, type: :model do
  describe "validations" do
    it { is_expected.to validate_presence_of(:placed_at) }
    it { is_expected.to validate_length_of(:currency).is_equal_to(3) }

    it "rejects invalid status" do
      order = build(:order, status: "bogus")
      expect(order).not_to be_valid
    end

    it "auto-assigns an order_number on create when blank" do
      order = build(:order, order_number: nil)
      order.save!
      expect(order.order_number).to match(/\ASO-\d{6}-[A-F0-9]{8}\z/)
    end

    it "enforces unique order_number" do
      create(:order, order_number: "SO-123")
      dup = build(:order, order_number: "SO-123")
      expect(dup).not_to be_valid
    end
  end

  describe "#shopify_linked?" do
    it "true when shopify_order_id present" do
      expect(build(:order, :from_shopify).shopify_linked?).to be true
    end

    it "false for manual orders" do
      expect(build(:order).shopify_linked?).to be false
    end
  end

  describe "scopes" do
    it "recent orders placed_at DESC" do
      older = create(:order, placed_at: 5.days.ago)
      newer = create(:order, placed_at: 1.day.ago)
      expect(Order.recent.to_a).to eq([newer, older])
    end

    it "last_30_days excludes old orders" do
      create(:order, placed_at: 40.days.ago)
      create(:order, placed_at: 5.days.ago)
      expect(Order.last_30_days.count).to eq(1)
    end
  end
end
