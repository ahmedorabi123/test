require "rails_helper"

RSpec.describe Accounting::PostSaleJournalHandler do
  # COA accounts required by the handler
  let!(:ar_account)       { create(:account, code: "1100", name: "Accounts Receivable",  account_type: "asset",     normal_side: "debit") }
  let!(:revenue_account)  { create(:account, code: "4000", name: "Sales Revenue",         account_type: "revenue",   normal_side: "credit") }
  let!(:tax_account)      { create(:account, code: "2200", name: "Sales Tax Payable",     account_type: "liability", normal_side: "credit") }
  let!(:shipping_account) { create(:account, code: "4100", name: "Shipping Revenue",      account_type: "revenue",   normal_side: "credit") }

  let(:paid_order) do
    create(:order,
      financial_status: "paid",
      subtotal_price:   100.00,
      total_discount:   10.00,
      total_tax:        8.00,
      total_shipping:   5.00,
      total_price:      103.00)
  end

  describe ".call" do
    it "creates a posted journal entry for a paid order" do
      entry = described_class.call(paid_order)
      expect(entry).to be_a(JournalEntry)
      expect(entry.status).to eq("posted")
      expect(entry.entry_type).to eq("sale")
      expect(entry.source_type).to eq("order")
      expect(entry.source_id).to eq(paid_order.id)
    end

    it "debits A/R for the total_price" do
      entry = described_class.call(paid_order)
      debit_line = entry.journal_lines.find { |l| l.side == "debit" }
      expect(debit_line.account).to eq(ar_account)
      expect(debit_line.amount).to eq(paid_order.total_price)
    end

    it "credits sales revenue for subtotal minus discount" do
      entry = described_class.call(paid_order)
      rev_line = entry.journal_lines.find { |l| l.account == revenue_account }
      expect(rev_line.side).to eq("credit")
      expect(rev_line.amount).to eq(paid_order.subtotal_price - paid_order.total_discount)
    end

    it "credits sales tax payable when tax > 0" do
      entry = described_class.call(paid_order)
      tax_line = entry.journal_lines.find { |l| l.account == tax_account }
      expect(tax_line).not_to be_nil
      expect(tax_line.side).to eq("credit")
      expect(tax_line.amount).to eq(paid_order.total_tax)
    end

    it "credits shipping revenue when shipping > 0" do
      entry = described_class.call(paid_order)
      ship_line = entry.journal_lines.find { |l| l.account == shipping_account }
      expect(ship_line).not_to be_nil
      expect(ship_line.side).to eq("credit")
      expect(ship_line.amount).to eq(paid_order.total_shipping)
    end

    it "is idempotent — returns nil on second call" do
      described_class.call(paid_order)
      result = described_class.call(paid_order)
      expect(result).to be_nil
      expect(JournalEntry.where(source_id: paid_order.id).count).to eq(1)
    end

    it "skips unpaid orders" do
      pending_order = create(:order, financial_status: "pending", total_price: 50.00)
      result = described_class.call(pending_order)
      expect(result).to be_nil
      expect(JournalEntry.count).to eq(0)
    end

    it "creates a balanced entry (debits == credits)" do
      entry = described_class.call(paid_order)
      debits  = entry.journal_lines.select { |l| l.side == "debit"  }.sum(&:amount)
      credits = entry.journal_lines.select { |l| l.side == "credit" }.sum(&:amount)
      expect(debits).to be_within(0.01).of(credits)
    end

    context "when order has no tax" do
      let(:no_tax_order) do
        create(:order, financial_status: "paid",
          subtotal_price: 50.00, total_discount: 0, total_tax: 0, total_shipping: 5.00, total_price: 55.00)
      end

      it "omits the tax line" do
        entry = described_class.call(no_tax_order)
        tax_line = entry.journal_lines.find { |l| l.account == tax_account }
        expect(tax_line).to be_nil
      end
    end

    context "when order has no shipping" do
      let(:no_ship_order) do
        create(:order, financial_status: "paid",
          subtotal_price: 50.00, total_discount: 0, total_tax: 4.00, total_shipping: 0, total_price: 54.00)
      end

      it "omits the shipping line" do
        entry = described_class.call(no_ship_order)
        ship_line = entry.journal_lines.find { |l| l.account == shipping_account }
        expect(ship_line).to be_nil
      end
    end
  end
end
