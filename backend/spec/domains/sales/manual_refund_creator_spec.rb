require "rails_helper"

RSpec.describe Sales::ManualRefundCreator do
  let!(:revenue_account)  { create(:account, code: "4000", name: "Sales Revenue",     account_type: "revenue",   normal_side: "credit") }
  let!(:tax_account)      { create(:account, code: "2200", name: "Sales Tax Payable", account_type: "liability", normal_side: "credit") }
  let!(:shipping_account) { create(:account, code: "4100", name: "Shipping Revenue",  account_type: "revenue",   normal_side: "credit") }
  let!(:ar_account)       { create(:account, code: "1100", name: "Accounts Receivable", account_type: "asset",  normal_side: "debit") }

  let(:warehouse) { create(:warehouse) }
  let(:product)   { create(:product) }
  let(:variant)   { create(:variant, product: product, price: 25.00) }
  let(:order) do
    create(:order,
      financial_status: "paid",
      subtotal_price:   100.00,
      total_tax:        0.00,
      total_shipping:   0.00,
      total_discount:   0.00,
      total_price:      100.00)
  end
  let!(:line_item) do
    create(:order_line_item,
      order: order, variant: variant, sku: variant.sku,
      quantity: 4, price: 25.00, line_total: 100.00)
  end

  describe "validation" do
    it "rejects missing order_id" do
      expect {
        described_class.call(amount: "5.00")
      }.to raise_error(described_class::InvalidInput, /order_id/)
    end

    it "rejects missing amount" do
      expect {
        described_class.call(order_id: order.id)
      }.to raise_error(described_class::InvalidInput, /amount/)
    end

    it "rejects amount > remaining refundable" do
      expect {
        described_class.call(order_id: order.id, amount: "1000.00")
      }.to raise_error(described_class::InvalidInput, /exceeds/)
    end

    it "rejects restock without warehouse" do
      expect {
        described_class.call(order_id: order.id, amount: "10", restock: true)
      }.to raise_error(described_class::InvalidInput, /restock_warehouse_id/)
    end
  end

  it "creates a refund and flags order partially_refunded" do
    refund = described_class.call(
      order_id: order.id, amount: "20.00", reason: "customer_change"
    )
    expect(refund).to be_persisted
    expect(refund.amount).to eq(20.00)
    expect(order.reload.financial_status).to eq("partially_refunded")
  end

  it "flags fully_refunded when amount equals total_price" do
    described_class.call(order_id: order.id, amount: "100.00")
    expect(order.reload.financial_status).to eq("refunded")
  end

  it "respects already-applied refunds for remaining calc" do
    create(:refund, order: order, amount: 60.00)
    expect {
      described_class.call(order_id: order.id, amount: "50.00")
    }.to raise_error(described_class::InvalidInput, /exceeds/)
  end

  context "with restock" do
    let!(:stock_item) do
      create(:stock_item, variant: variant, warehouse: warehouse, quantity_on_hand: 0)
    end

    it "writes inventory back to the chosen warehouse" do
      refund = described_class.call(
        order_id: order.id, amount: "50.00",
        restock: true, restock_warehouse_id: warehouse.id,
        line_items: [{ order_line_item_id: line_item.id, quantity: 2, subtotal: "50.00" }]
      )
      expect(refund.refund_line_items.count).to eq(1)
      expect(stock_item.reload.quantity_on_hand).to eq(2)
      expect(StockMovement.where(reason: "refund_restock").count).to eq(1)
    end
  end
end
