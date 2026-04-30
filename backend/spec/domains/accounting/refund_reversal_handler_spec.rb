require "rails_helper"

RSpec.describe Accounting::RefundReversalHandler do
  let!(:ar_account)       { create(:account, code: "1100", name: "Accounts Receivable",  account_type: "asset",     normal_side: "debit") }
  let!(:revenue_account)  { create(:account, code: "4000", name: "Sales Revenue",         account_type: "revenue",   normal_side: "credit") }
  let!(:tax_account)      { create(:account, code: "2200", name: "Sales Tax Payable",     account_type: "liability", normal_side: "credit") }
  let!(:shipping_account) { create(:account, code: "4100", name: "Shipping Revenue",      account_type: "revenue",   normal_side: "credit") }

  let(:order) do
    create(:order,
      financial_status: "paid",
      subtotal_price:   100.00,
      total_discount:   0.00,
      total_tax:        8.00,
      total_shipping:   5.00,
      total_price:      113.00)
  end

  # Post the original sale first, then mark as refunded
  let!(:sale_entry) { Accounting::PostSaleJournalHandler.call(order) }
  let(:refunded_order) { order.tap { |o| o.update!(financial_status: "refunded") } }

  describe ".call" do
    it "creates a reversal entry" do
      reversal = described_class.call(refunded_order)
      expect(reversal).to be_a(JournalEntry)
      expect(reversal.status).to eq("posted")
    end

    it "marks the original entry as reversed" do
      described_class.call(refunded_order)
      expect(sale_entry.reload.status).to eq("reversed")
    end

    it "reversal entry references the original via reversal_of_id" do
      reversal = described_class.call(refunded_order)
      expect(reversal.reversal_of_id).to eq(sale_entry.id)
    end

    it "reversal lines are opposite of original lines" do
      reversal = described_class.call(refunded_order)
      original_debits  = sale_entry.journal_lines.select { |l| l.side == "debit" }.sum(&:amount)
      reversal_credits = reversal.journal_lines.select { |l| l.side == "credit" }.sum(&:amount)
      expect(reversal_credits).to be_within(0.01).of(original_debits)

      original_credits = sale_entry.journal_lines.select { |l| l.side == "credit" }.sum(&:amount)
      reversal_debits  = reversal.journal_lines.select { |l| l.side == "debit" }.sum(&:amount)
      expect(reversal_debits).to be_within(0.01).of(original_credits)
    end

    it "is idempotent — returns nil on second call" do
      described_class.call(refunded_order)
      result = described_class.call(refunded_order)
      expect(result).to be_nil
      expect(JournalEntry.reversed.count).to eq(1)
    end

    it "skips if no original sale entry exists" do
      orphan_order = create(:order, financial_status: "refunded", total_price: 50.00)
      result = described_class.call(orphan_order)
      expect(result).to be_nil
    end

    it "skips if order is not refunded" do
      result = described_class.call(order) # still 'paid'
      expect(result).to be_nil
    end
  end
end
