require "rails_helper"

RSpec.describe Sales::Shopify::OrderUpserter do
  let(:linked_variant) do
    create(:variant, :from_shopify, shopify_variant_id: 88_001, sku: "TEE-S")
  end

  let(:payload) do
    {
      "id"                => 9_001,
      "name"              => "#1001",
      "currency"          => "USD",
      "financial_status"  => "paid",
      "fulfillment_status"=> nil,
      "subtotal_price"    => "100.00",
      "total_tax"         => "8.00",
      "total_discounts"   => "0.00",
      "total_price"       => "113.00",
      "email"             => "shopper@example.com",
      "processed_at"      => "2026-04-20T10:00:00Z",
      "updated_at"        => "2026-04-20T10:05:00Z",
      "customer"          => { "first_name" => "Jane", "last_name" => "Doe" },
      "shipping_address"  => { "city" => "Brooklyn", "country" => "US" },
      "billing_address"   => {},
      "shipping_lines"    => [ { "price" => "5.00" } ],
      "line_items" => [
        {
          "id"         => 7_001,
          "variant_id" => 88_001,
          "sku"        => "TEE-S",
          "title"      => "Classic Tee",
          "variant_title" => "Black / S",
          "quantity"   => 2,
          "price"      => "49.50"
        }
      ]
    }
  end

  before { linked_variant }

  it "creates an Order with its line items and links to catalog variant" do
    expect {
      described_class.call(payload)
    }.to change(Order, :count).by(1).and change(OrderLineItem, :count).by(1)

    order = Order.find_by(shopify_order_id: 9_001)
    expect(order.order_number).to eq("#1001")
    expect(order.source).to eq("shopify")
    expect(order.financial_status).to eq("paid")
    expect(order.currency).to eq("USD")
    expect(order.total_price).to eq(113.00)
    expect(order.total_shipping).to eq(5.00)
    expect(order.customer_email).to eq("shopper@example.com")
    expect(order.customer_name).to eq("Jane Doe")
    expect(order.line_items.first.variant).to eq(linked_variant)
    expect(order.line_items.first.line_total).to eq(99.00) # 49.50 * 2
  end

  it "is idempotent — re-running with same payload doesn't duplicate" do
    described_class.call(payload)
    expect { described_class.call(payload) }.not_to change(Order, :count)
  end

  it "updates mutable fields on re-sync" do
    described_class.call(payload)
    payload["financial_status"] = "refunded"
    payload["updated_at"]       = "2026-04-21T10:00:00Z"
    described_class.call(payload)
    expect(Order.first.financial_status).to eq("refunded")
  end

  it "does not overwrite newer local state with older Shopify payload" do
    described_class.call(payload)
    # Simulate a later Shopify update
    payload["financial_status"] = "paid"
    payload["updated_at"]       = "2026-04-21T10:00:00Z"
    described_class.call(payload)

    # Now send an OLDER payload
    payload["financial_status"] = "pending"
    payload["updated_at"]       = "2026-04-19T10:00:00Z"
    described_class.call(payload)

    expect(Order.first.financial_status).to eq("paid")
  end

  it "marks the order cancelled when cancelled_at is set" do
    payload["cancelled_at"] = "2026-04-20T12:00:00Z"
    order = described_class.call(payload)
    expect(order.status).to eq("cancelled")
    expect(order.cancelled_at).to be_present
  end

  it "handles missing/unknown variants gracefully" do
    payload["line_items"].first["variant_id"] = 999_999
    order = described_class.call(payload)
    expect(order.line_items.first.variant).to be_nil
    expect(order.line_items.first.sku).to eq("TEE-S")
  end

  it "prunes line items removed from Shopify" do
    described_class.call(payload)

    payload["updated_at"] = "2026-04-20T11:00:00Z"
    payload["line_items"] = [
      {
        "id" => 7_001, "sku" => "TEE-S", "title" => "Classic Tee",
        "quantity" => 1, "price" => "49.50"
      },
      {
        "id" => 7_002, "sku" => "TEE-M", "title" => "Classic Tee",
        "quantity" => 1, "price" => "49.50"
      }
    ]
    described_class.call(payload)
    expect(Order.first.line_items.count).to eq(2)

    payload["updated_at"] = "2026-04-20T12:00:00Z"
    payload["line_items"].pop
    described_class.call(payload)
    expect(Order.first.line_items.count).to eq(1)
  end
end

# ──────────────────────────────────────────────────────────────────────────────
# Accounting integration — Shopify order → journal entries
# ──────────────────────────────────────────────────────────────────────────────
RSpec.describe "Sales::Shopify::OrderUpserter → Accounting integration" do
  # COA accounts required by PostSaleJournalHandler
  let!(:ar_account)       { create(:account, code: "1100", name: "Accounts Receivable",  account_type: "asset",     normal_side: "debit") }
  let!(:revenue_account)  { create(:account, code: "4000", name: "Sales Revenue",         account_type: "revenue",   normal_side: "credit") }
  let!(:tax_account)      { create(:account, code: "2200", name: "Sales Tax Payable",     account_type: "liability", normal_side: "credit") }
  let!(:shipping_account) { create(:account, code: "4100", name: "Shipping Revenue",      account_type: "revenue",   normal_side: "credit") }

  let(:paid_payload) do
    {
      "id"               => 9_999,
      "name"             => "#2001",
      "currency"         => "USD",
      "financial_status" => "paid",
      "subtotal_price"   => "80.00",
      "total_tax"        => "6.40",
      "total_discounts"  => "0.00",
      "total_price"      => "91.40",
      "email"            => "customer@example.com",
      "processed_at"     => "2026-04-20T10:00:00Z",
      "updated_at"       => "2026-04-20T10:00:00Z",
      "shipping_lines"   => [{ "price" => "5.00" }],
      "line_items"       => []
    }
  end

  it "posts a journal entry when a paid order is upserted" do
    expect {
      Sales::Shopify::OrderUpserter.call(paid_payload)
    }.to change(JournalEntry, :count).by(1)

    entry = JournalEntry.last
    expect(entry.status).to eq("posted")
    expect(entry.entry_type).to eq("sale")
    debits  = entry.journal_lines.select { |l| l.side == "debit"  }.sum(&:amount)
    credits = entry.journal_lines.select { |l| l.side == "credit" }.sum(&:amount)
    expect(debits).to be_within(0.01).of(credits)
  end

  it "is idempotent — re-upserting a paid order does not duplicate journal entries" do
    Sales::Shopify::OrderUpserter.call(paid_payload)
    expect {
      paid_payload["updated_at"] = "2026-04-20T11:00:00Z"
      Sales::Shopify::OrderUpserter.call(paid_payload)
    }.not_to change(JournalEntry, :count)
  end

  it "creates a reversal when an order transitions from paid to refunded" do
    # First upsert as paid → creates sale journal entry
    Sales::Shopify::OrderUpserter.call(paid_payload)
    expect(JournalEntry.count).to eq(1)

    # Then Shopify sends a refund webhook
    refund_payload = paid_payload.merge(
      "financial_status" => "refunded",
      "updated_at"       => "2026-04-21T10:00:00Z"
    )
    expect {
      Sales::Shopify::OrderUpserter.call(refund_payload)
    }.to change(JournalEntry, :count).by(1)

    reversal = JournalEntry.order(:created_at).last
    expect(reversal.reversal_of_id).to be_present
    expect(JournalEntry.reversed.count).to eq(1)
  end

  it "does not create a journal entry for pending orders" do
    pending_payload = paid_payload.merge("financial_status" => "pending")
    expect {
      Sales::Shopify::OrderUpserter.call(pending_payload)
    }.not_to change(JournalEntry, :count)
  end

  it "does not crash the order upsert if accounting raises an error" do
    allow(Accounting::PostSaleJournalHandler).to receive(:call).and_raise(StandardError, "DB error")
    expect {
      Sales::Shopify::OrderUpserter.call(paid_payload)
    }.not_to raise_error
    # Order must still be persisted
    expect(Order.find_by(shopify_order_id: 9_999)).to be_present
  end
end
