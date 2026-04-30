require "rails_helper"

RSpec.describe Sales::OrderStateMachine do
  describe "status transitions" do
    let(:order) { create(:order) }

    it "moves pending → processing" do
      expect { described_class.call(order, to: "processing") }
        .to change { order.reload.status }.from("pending").to("processing")
    end

    it "moves pending → fulfilled" do
      described_class.call(order, to: "fulfilled")
      expect(order.reload.status).to eq("fulfilled")
    end

    it "moves any → cancelled and stamps cancelled_at" do
      described_class.call(order, to: "cancelled")
      order.reload
      expect(order.status).to eq("cancelled")
      expect(order.cancelled_at).to be_present
    end

    it "rejects illegal transitions" do
      order.update!(status: "cancelled", cancelled_at: Time.current)
      expect {
        described_class.call(order, to: "processing")
      }.to raise_error(Sales::OrderStateMachine::InvalidTransition)
    end
  end

  describe "financial transitions" do
    let(:order) { create(:order) }

    it "moves pending → authorized → paid" do
      described_class.call(order, to: "authorized")
      expect(order.reload.financial_status).to eq("authorized")
      described_class.call(order, to: "paid")
      expect(order.reload.financial_status).to eq("paid")
    end

    it "rejects paid → pending" do
      order.update!(financial_status: "paid")
      expect {
        described_class.call(order, to: "pending")
      }.to raise_error(Sales::OrderStateMachine::InvalidTransition)
    end
  end

  describe "unknown target" do
    it "raises InvalidTransition" do
      order = create(:order)
      expect {
        described_class.call(order, to: "wat")
      }.to raise_error(Sales::OrderStateMachine::InvalidTransition)
    end
  end
end
