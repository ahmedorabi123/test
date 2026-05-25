require "rails_helper"

RSpec.describe Accounting::PostCogsHandler do
  let(:order) { create(:order, financial_status: "paid", currency: "EGP") }
  let(:variant) { create(:variant, cost_per_item: 100.0) }
  let(:line_item) { create(:order_line_item, order: order, variant: variant, quantity: 2, price: 50.0) }
  let(:fulfillment) { create(:fulfillment, order: order, status: "success") }

  before do
    create(:account, code: "1200", name: "Inventory", account_type: "asset", normal_side: "debit")
    create(:account, code: "5000", name: "COGS", account_type: "expense", normal_side: "debit")
  end

  it "skips COGS while the feature gate is disabled" do
    fulfillment.fulfillment_line_items.create!(order_line_item: line_item, quantity: 2)

    expect { described_class.call(fulfillment) }.not_to change(JournalEntry, :count)
  end

  it "posts COGS from a persisted FIFO cost breakdown before variant fallback when enabled" do
    fulfillment.fulfillment_line_items.create!(
      order_line_item: line_item,
      quantity: 2,
      cost_breakdown: [
        { source: "fifo", quantity: 1, unit_cost: "5.0", total_cost: "5.0" },
        { source: "fifo", quantity: 1, unit_cost: "7.0", total_cost: "7.0" }
      ]
    )

    with_env("ACCOUNTING_COGS_ENABLED", "true") do
      described_class.call(fulfillment)
    end

    entry = JournalEntry.find_by!(idempotency_key: "cogs-#{fulfillment.id}")
    expect(entry.journal_lines.sum(:amount)).to eq(24.0)
    debit = entry.journal_lines.joins(:account).find_by!(accounts: { code: "5000" })
    expect(debit.amount).to eq(12.0)
  end

  def with_env(key, value)
    previous = ENV[key]
    ENV[key] = value
    yield
  ensure
    ENV[key] = previous
  end
end