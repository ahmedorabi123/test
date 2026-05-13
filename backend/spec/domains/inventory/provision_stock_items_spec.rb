require "rails_helper"

RSpec.describe Inventory::ProvisionStockItems do
  it "treats duplicate stock item creation as already provisioned" do
    variant = create(:variant)
    warehouse = create(:warehouse)
    create(:stock_item, variant: variant, warehouse: warehouse)

    expect {
      described_class.call(variant: variant, warehouses: Warehouse.where(id: warehouse.id))
    }.not_to change(StockItem, :count)
  end

  it "does not auto-provision showroom or transit warehouses" do
    variant = create(:variant)
    own = create(:warehouse, kind: "own")
    showroom = create(:warehouse, name: "Ahmed", code: "AHMED", kind: "consignment")
    transit = create(:warehouse, kind: "transit")

    described_class.call(variant: variant)

    expect(StockItem.where(variant: variant, warehouse: own)).to exist
    expect(StockItem.where(variant: variant, warehouse: showroom)).not_to exist
    expect(StockItem.where(variant: variant, warehouse: transit)).not_to exist
  end

  it "filters explicit warehouses to active own warehouses" do
    variant = create(:variant)
    own = create(:warehouse, kind: "own")
    consignment = create(:warehouse, kind: "consignment")

    described_class.call(variant: variant, warehouses: Warehouse.where(id: [own.id, consignment.id]))

    expect(StockItem.where(variant: variant, warehouse: own)).to exist
    expect(StockItem.where(variant: variant, warehouse: consignment)).not_to exist
  end
end
