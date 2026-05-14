require "rails_helper"

# End-to-end Shopify order lifecycle: create → paid → fulfilled → refund(restock).
# Verifies that all four side-effects (sales, inventory, shipping, accounting)
# compose correctly and are idempotent under duplicate webhook deliveries.
RSpec.describe "Shopify order lifecycle (end-to-end)", type: :request do
  let!(:warehouse) { create(:warehouse, shopify_location_id: 555, active: true) }
  let!(:product)   { create(:product) }
  let!(:variant)   { create(:variant, product: product, shopify_variant_id: 777) }
  let!(:stock_item){ create(:stock_item, variant: variant, warehouse: warehouse, quantity_on_hand: 50) }

  before do
    # Seed accounts the journal handlers need.
    {
      "1100" => %w[asset debit],
      "4000" => %w[revenue credit],
      "2200" => %w[liability credit],
      "4100" => %w[revenue credit]
    }.each do |code, (type, side)|
      Account.find_or_create_by!(code: code) do |a|
        a.name         = "Acct #{code}"
        a.account_type = type
        a.normal_side  = side
        a.currency     = "USD"
      end
    end
  end

  let(:order_id)       { 7_000_001 }
  let(:customer_id)    { 555_555 }
  let(:line_item_id)   { 9001 }
  let(:fulfillment_id) { 11_111 }
  let(:refund_id)      { 22_222 }

  let(:order_payload) do
    {
      "id"                => order_id,
      "name"              => "#SH-1001",
      "currency"          => "USD",
      "subtotal_price"    => "100.00",
      "total_tax"         => "8.00",
      "total_discounts"   => "0.00",
      "total_price"       => "113.00",
      "financial_status"  => "paid",
      "fulfillment_status"=> nil,
      "processed_at"      => "2026-04-20T10:00:00Z",
      "updated_at"        => "2026-04-20T10:00:00Z",
      "email"             => "buyer@example.com",
      "customer"          => { "id" => customer_id, "email" => "buyer@example.com", "first_name" => "Buy", "last_name" => "Er" },
      "shipping_lines"    => [ { "price" => "5.00" } ],
      "line_items" => [
        {
          "id"            => line_item_id,
          "variant_id"    => 777,
          "sku"           => variant.sku,
          "title"         => "Tee",
          "quantity"      => 4,
          "price"         => "25.00",
          "tax_lines"     => [],
          "discount_allocations" => []
        }
      ]
    }
  end

  let(:fulfillment_payload) do
    {
      "id"              => fulfillment_id,
      "order_id"        => order_id,
      "status"          => "success",
      "tracking_company"=> "Bosta",
      "tracking_number" => "BST-777",
      "tracking_url"    => "https://bosta.co/track/777",
      "location_id"     => 555,
      "created_at"      => "2026-04-21T10:00:00Z",
      "updated_at"      => "2026-04-21T10:00:00Z",
      "line_items"      => [ { "id" => line_item_id, "quantity" => 4, "variant_id" => 777 } ]
    }
  end

  let(:refund_payload) do
    {
      "id"              => refund_id,
      "order_id"        => order_id,
      "note"            => "customer change",
      "created_at"      => "2026-04-22T10:00:00Z",
      "processed_at"    => "2026-04-22T10:00:00Z",
      "transactions"    => [ { "amount" => "25.00", "kind" => "refund", "status" => "success" } ],
      "refund_line_items" => [
        {
          "id" => 1, "line_item_id" => line_item_id, "quantity" => 1,
          "subtotal" => "25.00", "restock_type" => "return", "location_id" => 555
        }
      ]
    }
  end

  it "processes create+paid → fulfillment → refund with full ledger integrity" do
    # 1. Order paid
    Sales::Shopify::OrderUpserter.call(order_payload, from: :webhook)

    order = Order.find_by(shopify_order_id: order_id)
    expect(order).to be_present
    expect(order.financial_status).to eq("paid")
    expect(order.line_items.count).to eq(1)

    sale_entry = JournalEntry.find_by(idempotency_key: "sale-journal-#{order.id}")
    expect(sale_entry).to be_present
    expect(sale_entry.total_debits).to eq(sale_entry.total_credits)
    expect(stock_item.reload.quantity_on_hand).to eq(50) # no deduction yet

    # 2. Fulfilled (triggers inventory deduction)
    Shipping::Shopify::FulfillmentUpserter.call(fulfillment_payload)
    expect(Fulfillment.count).to eq(1)
    expect(Fulfillment.first.bosta?).to be true
    expect(stock_item.reload.quantity_on_hand).to eq(46) # 50 - 4
    expect(order.reload.fulfillment_status).to eq("fulfilled")

    # 3. Partial refund with restock
    Sales::Shopify::RefundUpserter.call(refund_payload)
    expect(Refund.count).to eq(1)
    refund = Refund.first
    expect(refund.amount).to eq(25.00)
    expect(refund.partial?).to be true
    expect(stock_item.reload.quantity_on_hand).to eq(47) # restock +1
    partial_entry = JournalEntry.find_by(idempotency_key: "refund-partial-#{refund.id}")
    expect(partial_entry).to be_present
    expect(partial_entry.total_debits).to eq(partial_entry.total_credits)
    expect(order.reload.financial_status).to eq("partially_refunded")
  end

  it "is fully idempotent under duplicate webhook delivery of every topic" do
    # First delivery of each
    Sales::Shopify::OrderUpserter.call(order_payload, from: :webhook)
    Shipping::Shopify::FulfillmentUpserter.call(fulfillment_payload)
    Sales::Shopify::RefundUpserter.call(refund_payload)

    movements_before = StockMovement.count
    entries_before   = JournalEntry.count
    refunds_before   = Refund.count
    fulfillments_before = Fulfillment.count

    # Deliver each a second time
    Sales::Shopify::OrderUpserter.call(order_payload, from: :webhook)
    Shipping::Shopify::FulfillmentUpserter.call(fulfillment_payload)
    Sales::Shopify::RefundUpserter.call(refund_payload)

    expect(StockMovement.count).to eq(movements_before)
    expect(JournalEntry.count).to eq(entries_before)
    expect(Refund.count).to eq(refunds_before)
    expect(Fulfillment.count).to eq(fulfillments_before)
  end

  it "flips the order to refunded and posts a partial-refund journal entry when refunded in full" do
    Sales::Shopify::OrderUpserter.call(order_payload, from: :webhook)
    Shipping::Shopify::FulfillmentUpserter.call(fulfillment_payload)

    full_refund = refund_payload.deep_dup
    full_refund["transactions"] = [{ "amount" => "113.00", "kind" => "refund", "status" => "success" }]
    Sales::Shopify::RefundUpserter.call(full_refund)

    order = Order.find_by(shopify_order_id: order_id)
    expect(order.financial_status).to eq("refunded")
    expect(order.status).to eq("refunded")
    # Refund accounting is always via PartialRefundJournalHandler (avoids
    # double-counting when multiple partial refunds precede a full refund).
    refund = Refund.find_by(shopify_refund_id: full_refund["id"])
    expect(JournalEntry.find_by(idempotency_key: "refund-partial-#{refund.id}")).to be_present
    expect(JournalEntry.where(idempotency_key: "refund-reversal-#{order.id}")).not_to exist
  end
end
