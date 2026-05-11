require "rails_helper"

RSpec.describe Shipping::TransitionDelivery do
  let(:order) { create(:order, status: "fulfilled") }
  let(:fulfillment) do
    create(:fulfillment, order: order, status: "success", delivery_status: "pending")
  end

  describe ".call" do
    it "transitions pending → in_transit and stamps in_transit_at" do
      result = described_class.call(fulfillment, to: "in_transit")
      expect(result.delivery_status).to eq("in_transit")
      expect(result.in_transit_at).to be_present
    end

    it "transitions in_transit → delivered and stamps delivered_at" do
      fulfillment.update!(delivery_status: "in_transit", in_transit_at: 1.hour.ago)
      result = described_class.call(fulfillment, to: "delivered")
      expect(result.delivery_status).to eq("delivered")
      expect(result.delivered_at).to be_present
    end

    it "allows pending → delivered directly" do
      result = described_class.call(fulfillment, to: "delivered")
      expect(result.delivery_status).to eq("delivered")
    end

    it "is idempotent on same target" do
      fulfillment.update!(delivery_status: "delivered", delivered_at: 1.hour.ago)
      expect {
        described_class.call(fulfillment, to: "delivered")
      }.not_to change { fulfillment.reload.delivered_at }
    end

    it "rejects illegal transition delivered → in_transit" do
      fulfillment.update!(delivery_status: "delivered")
      expect {
        described_class.call(fulfillment, to: "in_transit")
      }.to raise_error(described_class::InvalidTransition)
    end

    it "rejects unknown status" do
      expect {
        described_class.call(fulfillment, to: "bogus")
      }.to raise_error(described_class::InvalidTransition)
    end

    it "records a ShipmentEvent" do
      expect {
        described_class.call(fulfillment, to: "in_transit", note: "left depot")
      }.to change { fulfillment.shipment_events.count }.by(1)
      ev = fulfillment.shipment_events.order(:created_at).last
      expect(ev.kind).to eq("in_transit")
    end

    it "records an audit log entry" do
      expect {
        described_class.call(fulfillment, to: "delivered")
      }.to change { AuditLog.where(action: "fulfillment.delivery_status_changed").count }.by(1)
    end
  end
end
