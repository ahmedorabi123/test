require "rails_helper"

RSpec.describe Inventory::ConsumeReservation do
  let(:warehouse) { create(:warehouse) }
  let(:variant) { create(:variant) }
  let(:stock_item) { create(:stock_item, variant: variant, warehouse: warehouse, quantity_on_hand: 8) }
  let(:order) { create(:order, status: "processing") }
  let(:line_item) do
    order.line_items.create!(variant: variant, title: "Item", quantity: 3, price: "10.00")
  end
  let(:fulfillment) { create(:fulfillment, order: order, status: "success") }

  it "consumes an active reservation, deducts on-hand, and updates fulfillment counters" do
    stock_item
    line_item
    Inventory::SyncOrderReservations.call(order, warehouse: warehouse)
    fulfillment_line_item = fulfillment.fulfillment_line_items.create!(
      order_line_item: line_item,
      quantity: 2
    )

    expect {
      described_class.call(fulfillment_line_item, warehouse: warehouse)
    }.to change(StockMovement, :count).by(1)

    expect(stock_item.reload.quantity_on_hand).to eq(6)
    expect(stock_item.quantity_reserved).to eq(1)
    expect(line_item.reload.fulfilled_quantity).to eq(2)
    expect(line_item.stock_reservations.active.sum(:quantity)).to eq(1)
  end

  it "is idempotent for the same fulfillment line item" do
    stock_item
    line_item
    Inventory::SyncOrderReservations.call(order, warehouse: warehouse)
    fulfillment_line_item = fulfillment.fulfillment_line_items.create!(
      order_line_item: line_item,
      quantity: 2
    )

    described_class.call(fulfillment_line_item, warehouse: warehouse)
    described_class.call(fulfillment_line_item, warehouse: warehouse)

    expect(stock_item.reload.quantity_on_hand).to eq(6)
    expect(line_item.reload.fulfilled_quantity).to eq(2)
    expect(
      StockMovement.where(
        reference_type: "FulfillmentLineItem",
        reference_id: fulfillment_line_item.id.to_s,
        reason: "fulfilled"
      ).count
    ).to eq(1)
  end
end
