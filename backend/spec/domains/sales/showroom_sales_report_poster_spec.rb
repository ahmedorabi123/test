require "rails_helper"

RSpec.describe Sales::ShowroomSalesReportPoster do
  let!(:ar_account)       { create(:account, code: "1100", name: "Accounts Receivable",  account_type: "asset",     normal_side: "debit") }
  let!(:revenue_account)  { create(:account, code: "4000", name: "Sales Revenue",         account_type: "revenue",   normal_side: "credit") }
  let!(:tax_account)      { create(:account, code: "2200", name: "Sales Tax Payable",     account_type: "liability", normal_side: "credit") }
  let!(:shipping_account) { create(:account, code: "4100", name: "Shipping Revenue",      account_type: "revenue",   normal_side: "credit") }
  let!(:cogs_account)     { create(:account, code: "5000", name: "Cost of Goods Sold",    account_type: "expense",   normal_side: "debit") }
  let!(:inventory_account) { create(:account, code: "1200", name: "Inventory",            account_type: "asset",     normal_side: "debit") }

  let(:showroom) { create(:warehouse, kind: "consignment", code: "CAIRO-SR", currency: "USD") }
  let(:own_wh)   { create(:warehouse, kind: "own") }
  let(:product)  { create(:product) }
  let(:variant)  { create(:variant, product: product, price: 50.00, cost_per_item: 20.00) }

  def sales_line(qty: 2, price: "50.00", v: variant)
    { variant_id: v.id, quantity: qty, unit_price: price }
  end

  describe "positive (sales) lines" do
    let(:line_items) { [sales_line(qty: 2)] }
    before { create(:stock_item, variant: variant, warehouse: showroom, quantity_on_hand: 5) }

    it "creates a fulfilled showroom order on the result" do
      result = described_class.call(warehouse_id: showroom.id, period: "2025-03", line_items: line_items)
      expect(result.order).to be_persisted
      expect(result.order.source).to eq("showroom")
      expect(result.order.status).to eq("fulfilled")
      expect(result.order.financial_status).to eq("paid")
      expect(result.order.notes).to include("[showroom:CAIRO-SR:2025-03]")
      expect(result.reversal).to be_nil
      expect(result.sales_total).to eq(100.to_d)
      expect(result.reversal_total).to eq(0)
    end

    it "deducts inventory from the showroom warehouse" do
      si = StockItem.find_by(variant: variant, warehouse: showroom)
      described_class.call(warehouse_id: showroom.id, period: "2025-03", line_items: line_items)
      expect(si.reload.quantity_on_hand).to eq(3)
      expect(StockMovement.where(reason: "showroom_sale").count).to eq(1)
    end

    it "posts a balanced sales journal entry and a COGS entry" do
      described_class.call(warehouse_id: showroom.id, period: "2025-03", line_items: line_items)
      sale_je = JournalEntry.where(entry_type: "sale", source_type: "order").last
      expect(sale_je).not_to be_nil
      expect(sale_je.journal_lines.where(side: "debit").sum(:amount)).to eq(
        sale_je.journal_lines.where(side: "credit").sum(:amount)
      )
      cogs_je = JournalEntry.where("idempotency_key LIKE 'cogs-order-%'").last
      expect(cogs_je.journal_lines.where(side: "debit").sum(:amount)).to eq(40.00) # 2 * 20
    end
  end

  describe "validation" do
    it "rejects non-consignment warehouses" do
      expect {
        described_class.call(warehouse_id: own_wh.id, period: "2025-03", line_items: [sales_line])
      }.to raise_error(described_class::InvalidInput, /consignment/)
    end

    it "rejects bad period format" do
      expect {
        described_class.call(warehouse_id: showroom.id, period: "March-2025", line_items: [sales_line])
      }.to raise_error(described_class::InvalidInput, /YYYY-MM/)
    end

    it "rejects empty line_items" do
      expect {
        described_class.call(warehouse_id: showroom.id, period: "2025-03", line_items: [])
      }.to raise_error(described_class::InvalidInput, /line_items/)
    end

    it "rejects zero quantity rows" do
      expect {
        described_class.call(warehouse_id: showroom.id, period: "2025-03",
                             line_items: [sales_line(qty: 0)])
      }.to raise_error(described_class::InvalidInput, /must not be zero/)
    end

    it "rejects duplicate variant rows on the same sign" do
      expect {
        described_class.call(warehouse_id: showroom.id, period: "2025-03",
                             line_items: [sales_line(qty: 1), sales_line(qty: 2)])
      }.to raise_error(described_class::InvalidInput, /duplicate/)
    end

    it "allows one positive and one negative line for the same variant" do
      v2 = create(:variant, product: product, price: 50.00, cost_per_item: 20.00)
      create(:stock_item, variant: variant, warehouse: showroom, quantity_on_hand: 5)
      create(:stock_item, variant: v2,      warehouse: showroom, quantity_on_hand: 5)
      expect {
        described_class.call(
          warehouse_id: showroom.id, period: "2025-03",
          line_items: [
            sales_line(qty: 1, v: variant),
            sales_line(qty: -1, v: variant),
            sales_line(qty: 1, v: v2)
          ]
        )
      }.not_to raise_error
    end
  end

  describe "idempotency" do
    before { create(:stock_item, variant: variant, warehouse: showroom, quantity_on_hand: 5) }

    it "is idempotent per warehouse+period for positive-only reports" do
      described_class.call(warehouse_id: showroom.id, period: "2025-03", line_items: [sales_line])
      expect {
        described_class.call(warehouse_id: showroom.id, period: "2025-03", line_items: [sales_line])
      }.to raise_error(described_class::AlreadyPosted)
    end

    it "is idempotent per warehouse+period for reversal-only reports" do
      described_class.call(warehouse_id: showroom.id, period: "2025-03",
                           line_items: [sales_line(qty: -1)])
      expect {
        described_class.call(warehouse_id: showroom.id, period: "2025-03",
                             line_items: [sales_line(qty: -1)])
      }.to raise_error(described_class::AlreadyPosted)
    end
  end

  describe "negative (reversal) lines" do
    it "does not create an Order or OrderLineItem" do
      expect {
        described_class.call(warehouse_id: showroom.id, period: "2025-04",
                             line_items: [sales_line(qty: -1, price: "50.00")])
      }.not_to change(Order, :count)
      expect(OrderLineItem.count).to eq(0)
    end

    it "does not move any stock" do
      si = create(:stock_item, variant: variant, warehouse: showroom, quantity_on_hand: 5)
      described_class.call(warehouse_id: showroom.id, period: "2025-04",
                           line_items: [sales_line(qty: -1, price: "50.00")])
      expect(si.reload.quantity_on_hand).to eq(5)
      expect(StockMovement.count).to eq(0)
    end

    it "creates a ShowroomReversal aggregate" do
      result = described_class.call(warehouse_id: showroom.id, period: "2025-04",
                                    line_items: [sales_line(qty: -2, price: "50.00")])
      expect(result.reversal).to be_a(ShowroomReversal)
      expect(result.reversal.total_amount).to eq(100.to_d)
      expect(result.reversal.lines.first["quantity"]).to eq(-2)
      expect(result.idempotency_key).to eq("showroom-reversal-#{showroom.id}-2025-04")
    end

    it "posts a DR 4000 / CR 1100 reversal journal" do
      described_class.call(warehouse_id: showroom.id, period: "2025-04",
                           line_items: [sales_line(qty: -2, price: "50.00")])
      je = JournalEntry.where("idempotency_key LIKE 'showroom-reversal-%'").last
      expect(je).not_to be_nil
      expect(je.entry_type).to eq("refund")
      debit_line = je.journal_lines.find { |l| l.side == "debit" }
      credit_line = je.journal_lines.find { |l| l.side == "credit" }
      expect(debit_line.account.code).to eq("4000")
      expect(credit_line.account.code).to eq("1100")
      expect(debit_line.amount).to eq(100.to_d)
      expect(je.journal_lines.sum { |l| l.side == "debit" ? l.amount : 0 })
        .to eq(je.journal_lines.sum { |l| l.side == "credit" ? l.amount : 0 })
    end

    it "does not create a Refund record" do
      expect {
        described_class.call(warehouse_id: showroom.id, period: "2025-04",
                             line_items: [sales_line(qty: -1, price: "50.00")])
      }.not_to change(Refund, :count)
    end
  end

  describe "mixed positive + negative" do
    let(:v2) { create(:variant, product: product, price: 30.00, cost_per_item: 10.00) }

    it "posts both the sale journal and the reversal journal" do
      create(:stock_item, variant: variant, warehouse: showroom, quantity_on_hand: 5)
      result = described_class.call(
        warehouse_id: showroom.id, period: "2025-05",
        line_items: [
          sales_line(qty: 2, price: "50.00", v: variant),
          sales_line(qty: -1, price: "30.00", v: v2)
        ]
      )
      expect(result.order).to be_persisted
      expect(result.reversal).to be_persisted
      expect(JournalEntry.where(entry_type: "sale", source_type: "order").count).to be >= 1
      expect(JournalEntry.where("idempotency_key LIKE 'showroom-reversal-%'").count).to eq(1)
    end
  end

  describe "atomicity" do
    it "rolls back the order when sale-journal posting fails" do
      create(:stock_item, variant: variant, warehouse: showroom, quantity_on_hand: 5)
      allow(Accounting::PostSaleJournalHandler).to receive(:call).and_raise(StandardError, "boom")
      expect {
        described_class.call(warehouse_id: showroom.id, period: "2025-06",
                             line_items: [sales_line(qty: 1)])
      }.to raise_error(StandardError, /boom/)
      expect(Order.count).to eq(0)
      expect(StockMovement.count).to eq(0)
    end

    it "rolls back the entire report when stock is insufficient" do
      create(:stock_item, variant: variant, warehouse: showroom, quantity_on_hand: 0)
      expect {
        described_class.call(warehouse_id: showroom.id, period: "2025-06",
                             line_items: [sales_line(qty: 5)])
      }.to raise_error(Inventory::WriteMovement::InsufficientStockError)
      expect(Order.count).to eq(0)
      expect(JournalEntry.count).to eq(0)
    end
  end
end
