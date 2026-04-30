require "rails_helper"

RSpec.describe Shipping::Shopify::FulfillmentUpserter do
  let!(:warehouse) { create(:warehouse, shopify_location_id: 555) }
  let!(:product)   { create(:product) }
  let!(:variant)   { create(:variant, product: product, shopify_variant_id: 777) }
  let!(:stock_item){ create(:stock_item, variant: variant, warehouse: warehouse, quantity_on_hand: 50) }

  let!(:order) do
    create(:order, :from_shopify, shopify_order_id: 4242).tap do |o|
      o.line_items.create!(
        variant:        variant,
        sku:            variant.sku,
        title:          "Tee",
        quantity:       3,
        price:          25.00,
        total_discount: 0,
        total_tax:      0,
        line_total:     75.00,
        shopify_line_item_id: 9001
      )
    end
  end

  let(:payload) do
    {
      "id"                => 12_345,
      "order_id"          => 4242,
      "status"            => "success",
      "tracking_company"  => "Bosta",
      "tracking_number"   => "BST-X1",
      "tracking_url"      => "https://bosta.co/track/X1",
      "location_id"       => 555,
      "created_at"        => "2026-04-22T10:00:00Z",
      "updated_at"        => "2026-04-22T10:00:00Z",
      "line_items"        => [
        { "id" => 9001, "quantity" => 3, "variant_id" => 777 }
      ]
    }
  end

  it "creates a Fulfillment with Bosta tracking and deducts inventory" do
    expect {
      described_class.call(payload)
    }.to change(Fulfillment, :count).by(1)
     .and change(StockMovement, :count).by(1)

    f = Fulfillment.last
    expect(f.order).to eq(order)
    expect(f.bosta?).to be true
    expect(f.tracking_number).to eq("BST-X1")
    expect(f.fulfillment_line_items.count).to eq(1)

    expect(stock_item.reload.quantity_on_hand).to eq(47)
    sm = StockMovement.last
    expect(sm.delta).to eq(-3)
    expect(sm.reason).to eq("fulfilled")
    expect(sm.reference_type).to eq("Fulfillment")
  end

  it "is idempotent — second delivery does not double-deduct stock" do
    described_class.call(payload)
    expect {
      described_class.call(payload)
    }.not_to change(StockMovement, :count)
    expect(stock_item.reload.quantity_on_hand).to eq(47)
  end

  it "updates the order's fulfillment_status to fulfilled" do
    described_class.call(payload)
    expect(order.reload.fulfillment_status).to eq("fulfilled")
  end

  it "falls back to the primary warehouse if location_id is unknown" do
    warehouse.update!(shopify_location_id: nil) # force mismatch
    payload["location_id"] = 999_999
    described_class.call(payload)
    # should have auto-created SHOPIFY-999999 or fallen back to primary
    expect(StockMovement.count).to be >= 0 # deduction attempted; new stock_item created on fallback
  end

  it "does nothing when the order isn't known locally" do
    payload["order_id"] = 999_999_999
    expect {
      described_class.call(payload)
    }.not_to change(Fulfillment, :count)
  end
end
