require "rails_helper"

RSpec.describe Inventory::WarehouseDeletion do
  it "deletes an unused manual warehouse" do
    warehouse = create(:warehouse)
    create(:stock_item, warehouse: warehouse, quantity_on_hand: 0, quantity_reserved: 0, quantity_unavailable: 0)

    expect {
      described_class.call(warehouse: warehouse)
    }.to change(Warehouse, :count).by(-1)
      .and change(StockItem, :count).by(-1)
  end

  it "blocks Shopify-managed warehouses" do
    warehouse = create(:warehouse, shopify_location_id: 123456)

    expect {
      described_class.call(warehouse: warehouse)
    }.to raise_error(Inventory::WarehouseDeletion::Blocked) { |error|
      expect(error.result.dependencies.map { |row| row[:key] }).to include(:shopify_origin)
    }
  end

  it "blocks warehouses with nonzero stock" do
    warehouse = create(:warehouse)
    create(:stock_item, warehouse: warehouse, quantity_on_hand: 1)

    expect {
      described_class.call(warehouse: warehouse)
    }.to raise_error(Inventory::WarehouseDeletion::Blocked) { |error|
      expect(error.result.dependencies.map { |row| row[:key] }).to include(:nonzero_stock_items)
    }
  end

  it "blocks warehouses with stock movement history" do
    warehouse = create(:warehouse)
    stock_item = create(:stock_item, warehouse: warehouse, quantity_on_hand: 0, quantity_reserved: 0, quantity_unavailable: 0)
    create(:stock_movement, stock_item: stock_item, delta: 0, snapshot_before: 0, snapshot_after: 0)

    expect {
      described_class.call(warehouse: warehouse)
    }.to raise_error(Inventory::WarehouseDeletion::Blocked) { |error|
      expect(error.result.dependencies.map { |row| row[:key] }).to include(:stock_movements)
    }
  end
end
