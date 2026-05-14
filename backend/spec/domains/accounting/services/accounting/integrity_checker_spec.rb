require "rails_helper"

RSpec.describe Accounting::IntegrityChecker do
  let!(:ar)   { create(:account, code: "1100", name: "AR",  account_type: "asset",   normal_side: "debit") }
  let!(:rev)  { create(:account, code: "4000", name: "Rev", account_type: "revenue", normal_side: "credit") }

  it "returns no errors for balanced posted entries" do
    JournalEntry.post!(
      { entry_date: Date.current, description: "OK" },
      [
        { account_code: "1100", side: "debit",  amount: 10 },
        { account_code: "4000", side: "credit", amount: 10 }
      ]
    )

    result = described_class.call
    expect(result[:errors]).to be_empty
    expect(result[:checked]).to be >= 1
  end

  it "flags an unbalanced entry that bypassed validation" do
    je = JournalEntry.post!(
      { entry_date: Date.current, description: "balanced for now" },
      [
        { account_code: "1100", side: "debit",  amount: 10 },
        { account_code: "4000", side: "credit", amount: 10 }
      ]
    )
    # Bypass validations to simulate a corrupted line.
    je.journal_lines.first.update_columns(amount: 99)

    result = described_class.call
    expect(result[:errors]).to be_present
    expect(result[:errors].first).to match(/unbalanced/i)
  end
end
