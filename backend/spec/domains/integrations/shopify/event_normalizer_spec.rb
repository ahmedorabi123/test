require "rails_helper"

RSpec.describe ::Shopify::EventNormalizer do
  describe ".normalize" do
    it "maps orders/create to :shopify_order_created" do
      payload = { "id" => 98765, "updated_at" => "2026-04-21T10:00:00Z", "name" => "#1001" }
      result  = described_class.normalize(topic: "orders/create", payload: payload)

      expect(result[:type]).to eq(:shopify_order_created)
      expect(result[:source]).to eq("shopify")
      expect(result[:topic]).to eq("orders/create")
      expect(result[:external_id]).to eq(98765)
      expect(result[:data]).to eq(payload)
      expect(result[:occurred_at]).to be_within(1.second).of(Time.zone.parse("2026-04-21T10:00:00Z"))
    end

    it "falls back to inventory_item_id for inventory_levels/update" do
      payload = { "inventory_item_id" => 42, "available" => 5 }
      result  = described_class.normalize(topic: "inventory_levels/update", payload: payload)
      expect(result[:type]).to eq(:shopify_inventory_updated)
      expect(result[:external_id]).to eq(42)
    end

    it "uses current time when no timestamp in payload" do
      result = described_class.normalize(topic: "orders/paid", payload: { "id" => 1 })
      expect(result[:occurred_at]).to be_within(5.seconds).of(Time.current)
    end

    it "raises on unsupported topic" do
      expect {
        described_class.normalize(topic: "orders/frobnicate", payload: {})
      }.to raise_error(described_class::UnsupportedTopicError)
    end
  end

  describe ".supports?" do
    it { expect(described_class.supports?("orders/paid")).to be true }
    it { expect(described_class.supports?("orders/frobnicate")).to be false }
  end
end
