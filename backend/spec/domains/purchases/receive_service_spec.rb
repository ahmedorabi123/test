require "rails_helper"

RSpec.describe Purchases::ReceiveService do
  let(:warehouse) { create(:warehouse) }
  let(:supplier)  { create(:supplier) }
  let(:product)   { create(:product) }
  let(:variant)   { create(:variant, product: product, price: "10.00") }

  before do
    create(:account, code: "1200", name: "Inventory", account_type: "asset", normal_side: "debit")
    create(:account, code: "1300", name: "Recoverable VAT", account_type: "asset", normal_side: "debit")
    create(:account, code: "2000", name: "Accounts Payable", account_type: "liability", normal_side: "credit")
  end

  it "receives inventory and bumps stock" do
    po = Purchases::PurchaseOrderCreator.call(
      supplier_id: supplier.id,
      warehouse_id: warehouse.id,
      line_items: [
        { variant_id: variant.id, quantity_ordered: 20, unit_cost: "6.00" }
      ]
    )
    li = po.line_items.first

    Purchases::ReceiveService.call(
      purchase_order: po,
      receipts: [{ line_item_id: li.id, quantity: 20 }],
      warehouse: warehouse
    )

    po.reload
    expect(po.status).to eq("received")
    expect(po.line_items.first.quantity_received).to eq(20)

    si = StockItem.find_by(variant: variant, warehouse: warehouse)
    expect(si.quantity_on_hand).to eq(20)
    expect(StockMovement.where(stock_item: si, reason: "received").count).to eq(1)
  end

  it "marks partial when only some received" do
    po = Purchases::PurchaseOrderCreator.call(
      supplier_id: supplier.id,
      warehouse_id: warehouse.id,
      line_items: [
        { variant_id: variant.id, quantity_ordered: 10, unit_cost: "6.00" }
      ]
    )
    li = po.line_items.first

    Purchases::ReceiveService.call(
      purchase_order: po,
      receipts: [{ line_item_id: li.id, quantity: 4 }],
      warehouse: warehouse
    )

    expect(po.reload.status).to eq("partial")
  end
end
