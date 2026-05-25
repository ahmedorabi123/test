require "rails_helper"

RSpec.describe Accounting::ManualJournalEntryDeletion do
  let!(:debit_account)  { create(:account, code: "1000", account_type: "asset",   normal_side: "debit") }
  let!(:credit_account) { create(:account, code: "4000", account_type: "revenue", normal_side: "credit") }

  def post_entry(entry_type:, amount: 100)
    JournalEntry.post!(
      { entry_date: Date.current, description: "Test #{entry_type}", currency: "USD", entry_type: entry_type },
      [
        { account_code: "1000", side: "debit",  amount: amount, currency: "USD", description: "DR" },
        { account_code: "4000", side: "credit", amount: amount, currency: "USD", description: "CR" }
      ]
    )
  end

  it "reverses a manual posted entry and marks the original as reversed" do
    entry  = post_entry(entry_type: "manual")
    result = described_class.call(entry)

    expect(result.original.reload.status).to eq("reversed")
    expect(result.reversal.status).to eq("posted")
    expect(result.reversal.reversal_of_id).to eq(entry.id)

    # Lines are flipped → net effect on both accounts is zero
    debit_lines  = JournalLine.joins(:account).where(accounts: { code: "1000" })
    credit_lines = JournalLine.joins(:account).where(accounts: { code: "4000" })
    expect(debit_lines.where(side: "debit").sum(:amount) - debit_lines.where(side: "credit").sum(:amount)).to eq(0)
    expect(credit_lines.where(side: "credit").sum(:amount) - credit_lines.where(side: "debit").sum(:amount)).to eq(0)
  end

  it "writes an audit log" do
    user  = create(:user)
    entry = post_entry(entry_type: "manual")
    expect {
      described_class.call(entry, actor: user)
    }.to change(AuditLog, :count).by(1)
    log = AuditLog.last
    expect(log.action).to eq("accounting.journal.manual_delete")
    expect(log.subject_type).to eq("JournalEntry")
    expect(log.subject_id).to eq(entry.id)
  end

  it "refuses non-manual entries" do
    sale = post_entry(entry_type: "sale")
    expect { described_class.call(sale) }.to raise_error(described_class::NotManualError)
    expect(sale.reload.status).to eq("posted")
  end

  it "refuses an already-reversed entry" do
    entry = post_entry(entry_type: "manual")
    described_class.call(entry)
    expect { described_class.call(entry.reload) }.to raise_error(described_class::NotPostedError)
  end

  it "refuses to reverse a reversal entry (no cascading reversals)" do
    entry  = post_entry(entry_type: "manual")
    result = described_class.call(entry)
    reversal = result.reversal
    expect(reversal.reversal_of_id).to eq(entry.id)
    expect(reversal.status).to eq("posted")
    # The reversal is itself entry_type=manual + posted, but it's a reversal —
    # we must refuse to reverse it again. Otherwise users can produce
    # ping-pong chains of meaningless reversal entries.
    expect {
      described_class.call(reversal)
    }.to raise_error(described_class::IsReversalError)
  end

  it "JournalEntry#reverse! itself blocks reversing a reversal" do
    entry  = post_entry(entry_type: "manual")
    reversal = entry.reverse!
    expect { reversal.reverse! }.to raise_error(RuntimeError, /Cannot reverse a reversal/)
  end
end
