require "rails_helper"

RSpec.describe Inventory::ReserveStockForOrder do
  let(:warehouse) { create(:warehouse) }
  let(:product)   { create(:product) }
  let(:variant)   { create(:variant, product: product) }
  let(:stock_item) do
    create(:stock_item, variant: variant, warehouse: warehouse,
           quantity_on_hand: 20, quantity_reserved: 0)
  end

  def build_order(status:, qty: 2)
    order = create(:order, status: status)
    order.line_items.create!(variant: variant, title: product.title, quantity: qty, price: "10.00")
    order
  end

  before { stock_item } # ensure stock exists

  describe ".call" do
    it "creates active reservation rows and recounts quantity_reserved" do
      order = build_order(status: "pending")
      described_class.call(order)
      expect(StockReservation.active.count).to eq(1)
      expect(stock_item.reload.quantity_reserved).to eq(2)
    end

    it "allows partial reservations for Shopify orders" do
      stock_item.update!(quantity_unavailable: 18) # only 2 effectively available
      order = create(:order, :from_shopify, status: "pending")
      order.line_items.create!(variant: variant, title: product.title, quantity: 10, price: "10.00")
      described_class.call(order)
      expect(stock_item.reload.quantity_reserved).to eq(2)
      expect(order.line_items.first.stock_reservations.active.first.note).to eq("partial")
    end

    it "raises for manual orders when inventory policy denies overselling" do
      stock_item.update!(quantity_unavailable: 18)
      order = build_order(status: "pending", qty: 10)
      expect { described_class.call(order) }.to raise_error(Inventory::Oversold)
    end

    it "is idempotent when called multiple times for same quantities" do
      order = build_order(status: "pending")
      described_class.call(order)
      described_class.call(order)
      expect(StockReservation.active.count).to eq(1)
      expect(stock_item.reload.quantity_reserved).to eq(2)
    end

    it "skips line items without a variant" do
      order = create(:order, status: "pending")
      order.line_items.create!(title: "Custom item", quantity: 1, price: "5.00")
      expect { described_class.call(order) }.not_to change { stock_item.reload.quantity_reserved }
    end
  end
end
