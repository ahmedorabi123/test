require "rails_helper"

RSpec.describe Accounting::PostShowroomReversalHandler do
  let!(:ar)      { create(:account, code: "1100", name: "A/R",          account_type: "asset",   normal_side: "debit") }
  let!(:revenue) { create(:account, code: "4000", name: "Sales Revenue", account_type: "revenue", normal_side: "credit") }

  let(:warehouse) { create(:warehouse, kind: "consignment", currency: "EGP") }
  let(:reversal) do
    ShowroomReversal.create!(
      warehouse:       warehouse,
      period:          "2025-03",
      currency:        "EGP",
      total_amount:    150.to_d,
      lines:           [{ variant_id: "v1", quantity: -3, unit_price: "50.00" }],
      idempotency_key: ShowroomReversal.build_idempotency_key(warehouse_id: warehouse.id, period: "2025-03"),
      posted_at:       Time.current
    )
  end

  it "posts a balanced DR 4000 / CR 1100 entry" do
    je = described_class.call(reversal)
    expect(je).to be_a(JournalEntry)
    expect(je.entry_type).to eq("refund")
    expect(je.source_type).to eq("showroom_reversal")
    expect(je.idempotency_key).to eq(reversal.idempotency_key)

    dr = je.journal_lines.find { |l| l.side == "debit" }
    cr = je.journal_lines.find { |l| l.side == "credit" }
    expect(dr.account.code).to eq("4000")
    expect(cr.account.code).to eq("1100")
    expect(dr.amount).to eq(150.to_d)
    expect(cr.amount).to eq(150.to_d)
  end

  it "is idempotent on the reversal's idempotency_key" do
    described_class.call(reversal)
    expect { described_class.call(reversal) }.not_to change(JournalEntry, :count)
  end

  it "skips when total_amount is zero" do
    reversal.update!(total_amount: 0)
    expect { described_class.call(reversal) }.not_to change(JournalEntry, :count)
  end
end
