require "rails_helper"

RSpec.describe Shipping::CreateManualFulfillment do
  let(:warehouse) { create(:warehouse, kind: "own") }
  let(:product)   { create(:product) }
  let(:variant)   { create(:variant, product: product, cost_per_item: 10.00) }
  let!(:stock_item) do
    create(:stock_item, variant: variant, warehouse: warehouse, quantity_on_hand: 10)
  end
  let!(:order) do
    o = create(:order, status: "pending", financial_status: "paid",
                       location_id: warehouse.shopify_location_id)
    create(:order_line_item, order: o, variant: variant, sku: variant.sku,
                             quantity: 2, price: 25.00, line_total: 50.00)
    o
  end

  before do
    [
      ["1100", "Accounts Receivable", "asset",   "debit"],
      ["4000", "Sales Revenue",       "revenue", "credit"],
      ["5000", "COGS",                "expense", "debit"],
      ["1200", "Inventory Asset",     "asset",   "debit"]
    ].each do |code, name, type, side|
      Account.find_or_create_by!(code: code) do |a|
        a.name = name; a.account_type = type; a.normal_side = side
      end
    end
  end

  it "creates a fulfillment record with tracking" do
    f = described_class.call(
      order:            order,
      tracking_company: "Bosta",
      tracking_number:  "BST123",
      tracking_url:     "https://bosta.example/BST123",
      transition_order: false
    )
    expect(f).to be_persisted
    expect(f.tracking_company).to eq("Bosta")
    expect(f.tracking_number).to eq("BST123")
    expect(f.status).to eq("success")
  end

  it "creates fulfillment line items linked to order line items" do
    oli = order.line_items.first
    f = described_class.call(
      order:            order,
      tracking_company: "Manual",
      transition_order: false,
      line_items:       [{ order_line_item_id: oli.id, quantity: 2 }]
    )
    expect(f.fulfillment_line_items.count).to eq(1)
    expect(f.fulfillment_line_items.first.quantity).to eq(2)
    expect(f.fulfillment_line_items.first.order_line_item_id).to eq(oli.id)
  end

  it "transitions the order to fulfilled and deducts stock" do
    expect {
      described_class.call(
        order:            order,
        tracking_company: "Bosta",
        tracking_number:  "X1",
        transition_order: true
      )
    }.to change { order.reload.status }.from("pending").to("fulfilled")
    expect(stock_item.reload.quantity_on_hand).to eq(8)
  end

  it "does not transition the order when transition_order is false" do
    described_class.call(
      order:            order,
      tracking_company: "Manual",
      transition_order: false
    )
    expect(order.reload.status).to eq("pending")
  end

  it "rejects missing tracking_company" do
    expect {
      described_class.call(order: order, tracking_company: "")
    }.to raise_error(Shipping::CreateManualFulfillment::InvalidInput)
  end
end
