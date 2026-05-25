require "rails_helper"

RSpec.describe Inventory::Shopify::StockSyncService do
  let!(:variant)  { create(:variant, :from_shopify) }

  def payload_for(available:, location_id: 99_001)
    {
      "inventory_item_id" => variant.shopify_inventory_item_id,
      "location_id"       => location_id,
      "available"         => available
    }
  end

  it "creates a StockItem and warehouse on first sync" do
    expect {
      described_class.call(payload_for(available: 15))
    }.to change(StockItem, :count).by(1).and change(Warehouse, :count).by(1)

    si = StockItem.last
    expect(si.quantity_on_hand).to eq(0)
    expect(si.shopify_quantity_on_hand).to eq(15)
    expect(si.warehouse.code).to eq("SHOPIFY-99001")
  end

  it "creates a StockMovement with correct delta" do
    expect {
      described_class.call(payload_for(available: 15))
    }.to change(StockMovement, :count).by(1)

    expect(StockMovement.last.delta).to eq(15)
    expect(StockMovement.last.reason).to eq("shopify_sync")
    expect(StockMovement.last.movement_scope).to eq("shopify_mirror")
  end

  it "updates existing StockItem and records delta movement" do
    warehouse = create(:warehouse, code: "SHOPIFY-99001", shopify_location_id: 99_001)
    create(:stock_item, variant: variant, warehouse: warehouse, quantity_on_hand: 10, shopify_quantity_on_hand: 10)
    expect {
      described_class.call(payload_for(available: 7))
    }.not_to change(StockItem, :count)

    expect(StockMovement.last.delta).to eq(-3)
    expect(StockItem.last.quantity_on_hand).to eq(10)
    expect(StockItem.last.shopify_quantity_on_hand).to eq(7)
  end

  it "does nothing when variant is not found" do
    result = described_class.call(payload_for(available: 5).merge("inventory_item_id" => 0))
    expect(result).to be_nil
  end

  it "does not create movement when quantity unchanged" do
    warehouse = create(:warehouse, code: "SHOPIFY-99001", shopify_location_id: 99_001)
    create(:stock_item, variant: variant, warehouse: warehouse, quantity_on_hand: 10, shopify_quantity_on_hand: 10)
    expect {
      described_class.call(payload_for(available: 10))
    }.not_to change(StockMovement, :count)
  end
end
