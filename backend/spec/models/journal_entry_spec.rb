require "rails_helper"

RSpec.describe JournalEntry, type: :model do
  let!(:debit_account)  { create(:account, code: "1000", account_type: "asset",   normal_side: "debit") }
  let!(:credit_account) { create(:account, code: "4000", account_type: "revenue", normal_side: "credit") }

  def build_posted_entry(amount: 100)
    JournalEntry.post!(
      { entry_date: Date.current, description: "Test Entry", currency: "USD", entry_type: "sale" },
      [
        { account_code: "1000", side: "debit",  amount: amount, currency: "USD", description: "DR" },
        { account_code: "4000", side: "credit", amount: amount, currency: "USD", description: "CR" }
      ]
    )
  end

  describe "validations" do
    it "validates presence of entry_date" do
      e = JournalEntry.new(description: "x", status: "draft", entry_date: nil)
      expect(e).not_to be_valid
      expect(e.errors[:entry_date]).to be_present
    end

    it "validates presence of description" do
      e = JournalEntry.new(entry_date: Date.current, status: "draft", description: "")
      expect(e).not_to be_valid
      expect(e.errors[:description]).to be_present
    end

    it "validates status inclusion" do
      e = JournalEntry.new(entry_date: Date.current, description: "x", status: "invalid")
      expect(e).not_to be_valid
      expect(e.errors[:status]).to be_present
    end

    it "rejects unbalanced lines when posting" do
      entry = JournalEntry.new(
        entry_date: Date.current,
        description: "Unbalanced",
        status: "posted",
        currency: "USD"
      )
      entry.journal_lines.build(account: debit_account, side: "debit", amount: 100, currency: "USD")
      entry.journal_lines.build(account: credit_account, side: "credit", amount: 90,  currency: "USD")
      expect(entry).not_to be_valid
      expect(entry.errors[:base].first).to match(/not balanced/)
    end

    it "accepts draft entries without balance check" do
      entry = JournalEntry.new(
        entry_date: Date.current,
        description: "Draft",
        status: "draft",
        currency: "USD"
      )
      entry.journal_lines.build(account: debit_account, side: "debit", amount: 100, currency: "USD")
      expect(entry).to be_valid
    end
  end

  describe ".post!" do
    it "creates a posted entry with balanced lines" do
      entry = build_posted_entry(amount: 200)
      expect(entry.status).to eq("posted")
      expect(entry.total_debits).to eq(200)
      expect(entry.total_credits).to eq(200)
    end

    it "raises ActiveRecord::RecordNotFound for unknown account_code" do
      expect {
        JournalEntry.post!(
          { entry_date: Date.current, description: "bad", currency: "USD" },
          [{ account_code: "NOPE", side: "debit", amount: 50, currency: "USD" }]
        )
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe "#reverse!" do
    it "creates an opposite entry and marks original reversed" do
      entry = build_posted_entry(amount: 150)
      reversal = entry.reverse!(description: "Test reversal")

      expect(reversal.status).to eq("posted")
      expect(reversal.reversal_of_id).to eq(entry.id)
      expect(entry.reload.status).to eq("reversed")
    end

    it "reversal lines are debits where original had credits and vice versa" do
      entry = build_posted_entry(amount: 150)
      reversal = entry.reverse!

      original_dr_amount = entry.journal_lines.find { |l| l.side == "debit" }.amount
      reversal_cr = reversal.journal_lines.select { |l| l.side == "credit" }.sum(&:amount)
      expect(reversal_cr).to be_within(0.01).of(original_dr_amount)
    end

    it "raises on non-posted entry" do
      entry = JournalEntry.create!(
        entry_date: Date.current, description: "Draft", status: "draft", currency: "USD"
      )
      expect { entry.reverse! }.to raise_error(RuntimeError, /Can only reverse a posted entry/)
    end
  end

  describe "scopes" do
    before do
      @posted   = build_posted_entry(amount: 50)
      @reversed = build_posted_entry(amount: 60)
      @reversed.reverse!
    end

    it "posted returns only posted entries" do
      expect(JournalEntry.posted).to include(@posted)
      expect(JournalEntry.posted).not_to include(@reversed)
    end

    it "reversed returns only reversed entries" do
      expect(JournalEntry.reversed).to include(@reversed)
      expect(JournalEntry.reversed).not_to include(@posted)
    end

    it "between filters by entry_date range" do
      old_entry = JournalEntry.create!(
        entry_date: 10.days.ago.to_date, description: "Old", status: "draft", currency: "USD"
      )
      recent = JournalEntry.between(5.days.ago.to_date, Date.current)
      expect(recent).to include(@posted)
      expect(recent).not_to include(old_entry)
    end
  end

  describe "#total_debits and #total_credits" do
    it "sums debits and credits from in-memory lines" do
      entry = build_posted_entry(amount: 300)
      expect(entry.total_debits).to eq(300)
      expect(entry.total_credits).to eq(300)
    end
  end
end
