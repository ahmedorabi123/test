require "rails_helper"

RSpec.describe Sales::ShowroomSalesReportPoster do
  let!(:ar_account)       { create(:account, code: "1100", name: "Accounts Receivable",  account_type: "asset",     normal_side: "debit") }
  let!(:revenue_account)  { create(:account, code: "4000", name: "Sales Revenue",         account_type: "revenue",   normal_side: "credit") }
  let!(:tax_account)      { create(:account, code: "2200", name: "Sales Tax Payable",     account_type: "liability", normal_side: "credit") }
  let!(:shipping_account) { create(:account, code: "4100", name: "Shipping Revenue",      account_type: "revenue",   normal_side: "credit") }
  let!(:cogs_account)     { create(:account, code: "5000", name: "Cost of Goods Sold",   account_type: "expense",   normal_side: "debit") }
  let!(:inventory_account) { create(:account, code: "1200", name: "Inventory",           account_type: "asset",     normal_side: "debit") }

  let(:showroom) { create(:warehouse, kind: "consignment", code: "CAIRO-SR", currency: "USD") }
  let(:own_wh)   { create(:warehouse, kind: "own") }
  let(:product)  { create(:product) }
  let(:variant)  { create(:variant, product: product, price: 50.00, cost_per_item: 20.00) }

  let(:line_items) do
    [{ variant_id: variant.id, quantity: 2, unit_price: "50.00" }]
  end

  it "creates a fulfilled showroom order" do
    order = described_class.call(
      warehouse_id: showroom.id, period: "2025-03",
      line_items: line_items
    )
    expect(order).to be_persisted
    expect(order.source).to eq("showroom")
    expect(order.status).to eq("fulfilled")
    expect(order.financial_status).to eq("paid")
    expect(order.notes).to include("[showroom:CAIRO-SR:2025-03]")
  end

  it "deducts inventory from the showroom warehouse" do
    si = create(:stock_item, variant: variant, warehouse: showroom, quantity_on_hand: 5)
    described_class.call(
      warehouse_id: showroom.id, period: "2025-03", line_items: line_items
    )
    expect(si.reload.quantity_on_hand).to eq(3)
    expect(StockMovement.where(reason: "showroom_sale").count).to eq(1)
  end

  it "is idempotent per warehouse+period" do
    described_class.call(
      warehouse_id: showroom.id, period: "2025-03", line_items: line_items
    )
    expect {
      described_class.call(
        warehouse_id: showroom.id, period: "2025-03", line_items: line_items
      )
    }.to raise_error(described_class::AlreadyPosted)
  end

  it "rejects non-consignment warehouses" do
    expect {
      described_class.call(
        warehouse_id: own_wh.id, period: "2025-03", line_items: line_items
      )
    }.to raise_error(described_class::InvalidInput, /consignment/)
  end

  it "rejects bad period format" do
    expect {
      described_class.call(
        warehouse_id: showroom.id, period: "March-2025", line_items: line_items
      )
    }.to raise_error(described_class::InvalidInput, /YYYY-MM/)
  end

  it "rejects empty line_items" do
    expect {
      described_class.call(
        warehouse_id: showroom.id, period: "2025-03", line_items: []
      )
    }.to raise_error(described_class::InvalidInput, /line_items/)
  end

  it "posts a balanced sales journal entry and a COGS entry" do
    described_class.call(
      warehouse_id: showroom.id, period: "2025-03", line_items: line_items
    )
    sale_je = JournalEntry.where(entry_type: "sale", source_type: "order").last
    expect(sale_je).not_to be_nil
    expect(sale_je.journal_lines.where(side: "debit").sum(:amount)).to eq(
      sale_je.journal_lines.where(side: "credit").sum(:amount)
    )

    cogs_je = JournalEntry.where("idempotency_key LIKE 'cogs-order-%'").last
    expect(cogs_je).not_to be_nil
    expect(cogs_je.journal_lines.where(side: "debit").sum(:amount)).to eq(40.00) # 2 * 20
  end
end
