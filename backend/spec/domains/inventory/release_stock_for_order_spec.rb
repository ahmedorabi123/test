require "rails_helper"

RSpec.describe Inventory::ReleaseStockForOrder do
  let(:warehouse)  { create(:warehouse) }
  let(:product)    { create(:product) }
  let(:variant)    { create(:variant, product: product) }
  let(:stock_item) do
    create(:stock_item, variant: variant, warehouse: warehouse,
           quantity_on_hand: 20, quantity_reserved: 5)
  end

  def build_order(qty: 3)
    order = create(:order, status: "pending")
    order.line_items.create!(variant: variant, title: product.title, quantity: qty, price: "10.00")
    order
  end

  before do
    stock_item.update!(quantity_reserved: 0)
  end

  describe ".call" do
    it "releases active reservations and recounts quantity_reserved" do
      order = build_order(qty: 3)
      Inventory::SyncOrderReservations.call(order, warehouse: warehouse)
      expect(stock_item.reload.quantity_reserved).to eq(3)

      described_class.call(order)
      expect(stock_item.reload.quantity_reserved).to eq(0)
      expect(order.stock_reservations.reload.pluck(:status)).to contain_exactly("released")
    end

    it "is idempotent" do
      order = build_order(qty: 10)
      Inventory::SyncOrderReservations.call(order, warehouse: warehouse)
      described_class.call(order)
      described_class.call(order)
      expect(stock_item.reload.quantity_reserved).to eq(0)
    end

    it "skips line items without a matching stock item" do
      other_variant = create(:variant)
      order = create(:order, status: "cancelled")
      order.line_items.create!(variant: other_variant, title: "Ghost", quantity: 1, price: "1.00")
      expect { described_class.call(order) }.not_to change { stock_item.reload.quantity_reserved }
    end
  end
end
