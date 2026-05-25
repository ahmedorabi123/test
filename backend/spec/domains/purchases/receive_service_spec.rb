require "rails_helper"

RSpec.describe Purchases::ReceiveService do
  let(:warehouse) { create(:warehouse) }
  let(:supplier)  { create(:supplier) }
  let(:product)   { create(:product) }
  let(:variant)   { create(:variant, product: product, price: "10.00") }

  it "receives inventory and bumps stock (Phase 1: no accounting / no cost layer)" do
    po = Purchases::PurchaseOrderCreator.call(
      supplier_id: supplier.id,
      warehouse_id: warehouse.id,
      line_items: [
        { variant_id: variant.id, quantity_ordered: 20 }
      ]
    )
    li = po.line_items.first

    expect {
      Purchases::ReceiveService.call(
        purchase_order: po,
        receipts: [{ line_item_id: li.id, quantity: 20 }],
        warehouse: warehouse
      )
    }.not_to change(JournalEntry, :count)

    po.reload
    expect(po.status).to eq("received")
    expect(po.line_items.first.quantity_received).to eq(20)

    si = StockItem.find_by(variant: variant, warehouse: warehouse)
    expect(si.quantity_on_hand).to eq(20)
    expect(StockMovement.where(stock_item: si, reason: "received").count).to eq(1)
    expect(StockCostLayer.where(stock_item: si).count).to eq(0)
    expect(variant.reload.last_purchase_cost.to_d).to eq(0.to_d)
  end

  it "marks partial when only some received" do
    po = Purchases::PurchaseOrderCreator.call(
      supplier_id: supplier.id,
      warehouse_id: warehouse.id,
      line_items: [
        { variant_id: variant.id, quantity_ordered: 10 }
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

  it "allows received quantities to be edited and adjusts system inventory by the delta" do
    shopify_warehouse = create(:warehouse, shopify_location_id: 12345)
    shopify_variant   = create(:variant, product: product, price: "10.00", shopify_variant_id: 9999)
    po = Purchases::PurchaseOrderCreator.call(
      supplier_id: supplier.id,
      warehouse_id: shopify_warehouse.id,
      line_items: [
        { variant_id: shopify_variant.id, quantity_ordered: 10 }
      ]
    )
    li = po.line_items.first

    Purchases::ReceiveService.call(
      purchase_order: po,
      receipts: [{ line_item_id: li.id, quantity: 10 }],
      warehouse: shopify_warehouse
    )

    si = StockItem.find_by!(variant: shopify_variant, warehouse: shopify_warehouse)
    Shopify::Origin.without_read_only do
      si.update!(shopify_quantity_on_hand: 4)
    end

    Purchases::EditReceiptService.call(
      purchase_order: po,
      line_items: [{ id: li.id, quantity_received: 7 }]
    )

    expect(si.reload.quantity_on_hand).to eq(7)
    expect(si.shopify_quantity_on_hand).to eq(4)
    expect(po.reload.status).to eq("partial")
    movement = StockMovement.where(stock_item: si, reason: "adjusted").last
    expect(movement.delta).to eq(-3)
  end

  it "rejects purchase orders against non-factory suppliers" do
    material_supplier = create(:supplier, kind: "material")
    expect {
      Purchases::PurchaseOrderCreator.call(
        supplier_id: material_supplier.id,
        warehouse_id: warehouse.id,
        line_items: [{ variant_id: variant.id, quantity_ordered: 5 }]
      )
    }.to raise_error(ActiveRecord::RecordInvalid, /factory supplier/)
  end
end

