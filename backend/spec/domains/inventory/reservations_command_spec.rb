require "rails_helper"

RSpec.describe Inventory::ReservationsCommand do
  let(:warehouse) { create(:warehouse) }
  let(:variant) { create(:variant) }
  let(:stock_item) { create(:stock_item, variant: variant, warehouse: warehouse, quantity_on_hand: 10) }
  let(:order) { create(:order, status: "pending") }
  let(:line_item) { create(:order_line_item, order: order, variant: variant, quantity: 4) }

  it "reserves, releases, and consumes through rows plus stock movement events" do
    expect {
      described_class.reserve(order_line_item: line_item, stock_item: stock_item, quantity: 4)
    }.to change { StockMovement.where(reason: "reserved").count }.by(1)

    expect(stock_item.reload.quantity_reserved).to eq(4)

    expect {
      described_class.release(order_line_item: line_item, quantity: 1)
    }.to change { StockMovement.where(reason: "reservation_released").count }.by(1)

    expect(stock_item.reload.quantity_reserved).to eq(3)

    expect {
      described_class.consume(order_line_item: line_item, quantity: 2, stock_item: stock_item)
    }.to change { StockMovement.where(reason: "reservation_consumed").count }.by(1)

    expect(stock_item.reload.quantity_reserved).to eq(1)
    expect(line_item.stock_reservations.active.sum(:quantity)).to eq(1)
  end

  it "records reservation reductions as release events" do
    described_class.reserve(order_line_item: line_item, stock_item: stock_item, quantity: 4)

    expect {
      described_class.reserve(order_line_item: line_item, stock_item: stock_item, quantity: 2)
    }.to change { StockMovement.where(reason: "reservation_released").count }.by(1)

    expect(stock_item.reload.quantity_reserved).to eq(2)
  end
end