require "rails_helper"

RSpec.describe Sales::Shopify::RefundUpserter do
  let!(:warehouse) { create(:warehouse, shopify_location_id: 555) }
  let!(:product)   { create(:product) }
  let!(:variant)   { create(:variant, product: product, shopify_variant_id: 777) }
  let!(:stock_item){ create(:stock_item, variant: variant, warehouse: warehouse, quantity_on_hand: 20) }

  let!(:order) do
    o = create(:order, :from_shopify,
               shopify_order_id: 9999,
               financial_status: "paid",
               subtotal_price:   100.00,
               total_tax:        8.00,
               total_shipping:   5.00,
               total_price:      113.00)
    o.line_items.create!(
      variant:        variant,
      sku:            variant.sku,
      title:          "Tee",
      quantity:       4,
      price:          25.00,
      total_discount: 0,
      total_tax:      0,
      line_total:     100.00,
      shopify_line_item_id: 8001
    )
    o
  end

  before do
    # Seed the minimum chart of accounts the journal handlers need.
    %w[1100 4000 2200 4100].each do |code|
      Account.find_or_create_by!(code: code) do |a|
        a.name         = "Account #{code}"
        a.account_type = (code == "1100" ? "asset" : (code == "2200" ? "liability" : "revenue"))
        a.normal_side  = (code == "1100" ? "debit" : "credit")
        a.currency     = "USD"
      end
    end
    # Post the original sale journal so partial/full reversal has something to reverse.
    Accounting::PostSaleJournalHandler.call(order)
  end

  def payload(amount: "25.00", restock: true, refund_id: 101)
    {
      "id"        => refund_id,
      "order_id"  => 9999,
      "note"      => "customer change",
      "created_at"   => "2026-04-22T10:00:00Z",
      "processed_at" => "2026-04-22T10:00:00Z",
      "transactions" => [ { "amount" => amount, "kind" => "refund", "status" => "success" } ],
      "refund_line_items" => [
        {
          "id" => 22, "line_item_id" => 8001, "quantity" => 1,
          "subtotal" => "25.00",
          "restock_type" => restock ? "return" : "no_restock",
          "location_id" => 555
        }
      ]
    }
  end

  describe "partial refund with restock" do
    it "creates a Refund, restocks inventory, and posts a partial refund journal" do
      expect {
        described_class.call(payload)
      }.to change(Refund, :count).by(1)
       .and change(StockMovement, :count).by(1)

      refund = Refund.last
      expect(refund.amount).to eq(25.00)
      expect(refund.restock?).to be true
      expect(refund.partial?).to be true
      expect(stock_item.reload.quantity_on_hand).to eq(21)
      expect(StockMovement.last.reason).to eq("refund_restock")

      partial_entry = JournalEntry.find_by(entry_type: "refund", idempotency_key: "refund-partial-#{refund.id}")
      expect(partial_entry).to be_present
      expect(partial_entry.status).to eq("posted")
    end

    it "transitions order financial_status appropriately" do
      described_class.call(payload)
      expect(order.reload.financial_status).to eq("partially_refunded")
    end
  end

  describe "full refund" do
    it "reverses the original sale journal and marks the order refunded" do
      described_class.call(payload(amount: "113.00", refund_id: 202))
      expect(order.reload.financial_status).to eq("refunded")
      expect(order.status).to eq("refunded")
      expect(JournalEntry.where(idempotency_key: "refund-reversal-#{order.id}")).to exist
    end
  end

  describe "no restock requested" do
    it "does not create stock movements" do
      expect {
        described_class.call(payload(restock: false))
      }.not_to change(StockMovement, :count)
    end
  end

  describe "idempotency" do
    it "ignores duplicate webhook delivery (same shopify_refund_id)" do
      described_class.call(payload)
      expect { described_class.call(payload) }.not_to change(Refund, :count)
      expect { described_class.call(payload) }.not_to change(StockMovement, :count)
    end
  end

  it "no-ops when the order is unknown" do
    p = payload
    p["order_id"] = 111_222
    expect {
      described_class.call(p)
    }.not_to change(Refund, :count)
  end
end
