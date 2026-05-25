require "rails_helper"

RSpec.describe Accounting::PostCogsReversalHandler do
  let(:warehouse) { create(:warehouse, kind: "own") }
  let(:product)   { create(:product) }
  let(:variant)   { create(:variant, product: product, cost_per_item: 12.50) }
  let(:order) do
    o = create(:order, financial_status: "paid", currency: "EGP")
    create(:order_line_item, order: o, variant: variant, sku: variant.sku,
                             quantity: 2, price: 25.00, line_total: 50.00)
    o
  end

  before do
    [
      ["1100", "Accounts Receivable", "asset",   "debit"],
      ["1200", "Inventory Asset",     "asset",   "debit"],
      ["4000", "Sales Revenue",       "revenue", "credit"],
      ["5000", "COGS",                "expense", "debit"]
    ].each do |code, name, type, side|
      Account.find_or_create_by!(code: code) do |a|
        a.name = name; a.account_type = type; a.normal_side = side
      end
    end
  end

  def make_refund(status: "processed", restock: true, restock_type: "return", quantity: 2)
    refund = create(:refund, order: order, amount: 25.00, restock: restock,
                             status: status, processed_at: Time.current)
    RefundLineItem.create!(
      refund:             refund,
      order_line_item:    order.line_items.first,
      quantity:           quantity,
      subtotal:           25.00,
      restock_type:       restock_type
    )
    refund
  end

  it "skips COGS reversals while the feature gate is disabled" do
    refund = make_refund
    expect {
      described_class.call(refund.reload)
    }.not_to change { JournalEntry.count }
  end

  it "posts a DR 1200 / CR 5000 entry for restock_type='return' lines when enabled" do
    refund = make_refund
    with_env("ACCOUNTING_COGS_ENABLED", "true") do
      expect {
        described_class.call(refund.reload)
      }.to change { JournalEntry.where(entry_type: "refund").count }.by(1)
    end

    entry = JournalEntry.where(idempotency_key: "cogs-reversal-#{refund.id}").first
    expect(entry).to be_present
    debit = entry.journal_lines.joins(:account).where(accounts: { code: "1200" }).first
    credit = entry.journal_lines.joins(:account).where(accounts: { code: "5000" }).first
    expect(debit.side).to eq("debit")
    expect(debit.amount).to eq(25.0)  # 12.50 * 2
    expect(credit.side).to eq("credit")
    expect(credit.amount).to eq(25.0)
  end

  it "is idempotent (no duplicate entry on second call)" do
    refund = make_refund
    with_env("ACCOUNTING_COGS_ENABLED", "true") do
      described_class.call(refund.reload)
      expect {
        described_class.call(refund.reload)
      }.not_to change { JournalEntry.count }
    end
  end

  it "skips when refund is not processed" do
    refund = make_refund(status: "draft")
    with_env("ACCOUNTING_COGS_ENABLED", "true") do
      expect {
        described_class.call(refund.reload)
      }.not_to change { JournalEntry.count }
    end
  end

  it "skips lines with restock_type='no_restock'" do
    refund = make_refund(restock_type: "no_restock")
    with_env("ACCOUNTING_COGS_ENABLED", "true") do
      expect {
        described_class.call(refund.reload)
      }.not_to change { JournalEntry.count }
    end
  end

  it "falls back to refund.restock? when restock_type is blank" do
    refund = make_refund(restock_type: nil, restock: true)
    with_env("ACCOUNTING_COGS_ENABLED", "true") do
      expect {
        described_class.call(refund.reload)
      }.to change { JournalEntry.count }.by(1)
    end
  end

  it "skips when total cost is zero" do
    variant.update!(cost_per_item: 0, cost: 0)
    refund = make_refund
    with_env("ACCOUNTING_COGS_ENABLED", "true") do
      expect {
        described_class.call(refund.reload)
      }.not_to change { JournalEntry.count }
    end
  end

  def with_env(key, value)
    previous = ENV[key]
    ENV[key] = value
    yield
  ensure
    ENV[key] = previous
  end
end
