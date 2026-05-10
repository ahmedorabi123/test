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
end
