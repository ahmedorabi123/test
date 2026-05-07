require "rails_helper"

RSpec.describe Accounting::PartialRefundJournalHandler do
  let(:order) do
    create(
      :order,
      financial_status: "paid",
      currency: "EGP",
      subtotal_price: "100.00",
      total_tax: "14.00",
      total_shipping: "0.00",
      total_price: "114.00"
    )
  end
  let!(:line_item) do
    order.line_items.create!(
      title: "Item",
      quantity: 2,
      price: "50.00",
      line_total: "100.00"
    )
  end
  let(:refund) do
    create(:refund, order: order, amount: "50.00", currency: "EGP", processed_at: Time.current)
  end

  before do
    seed_accounts
    refund.refund_line_items.create!(order_line_item: line_item, quantity: 1, subtotal: "50.00")
  end

  it "posts a balanced partial refund journal" do
    expect {
      described_class.call(refund)
    }.to change(JournalEntry, :count).by(1)

    entry = JournalEntry.find_by!(idempotency_key: "refund-partial-#{refund.id}")
    expect(entry.source_type).to eq("refund")
    expect(entry.source_id).to eq(refund.id)
    expect(entry.total_debits).to eq(entry.total_credits)
  end

  it "is idempotent for repeated calls" do
    described_class.call(refund)

    expect {
      described_class.call(refund)
    }.not_to change(JournalEntry, :count)
  end

  def seed_accounts
    {
      "1100" => %w[asset debit],
      "4000" => %w[revenue credit],
      "2200" => %w[liability credit],
      "4100" => %w[revenue credit]
    }.each do |code, (type, side)|
      Account.find_or_create_by!(code: code) do |account|
        account.name = "Account #{code}"
        account.account_type = type
        account.normal_side = side
        account.currency = "EGP"
      end
    end
  end
end
