# frozen_string_literal: true

module Accounting
  # Lightweight read-only integrity checker. Verifies:
  #   1. Every posted JournalEntry has equal debits and credits (within 0.01).
  #   2. No JournalLine references a missing account.
  #   3. No JournalEntry has zero lines.
  #
  # Returns: { errors: [String, ...], checked: Integer }
  class IntegrityChecker
    def self.call
      new.call
    end

    def call
      errors = []
      checked = 0

      JournalEntry.where(status: "posted").includes(:journal_lines).find_each(batch_size: 200) do |je|
        checked += 1
        lines = je.journal_lines.to_a

        if lines.empty?
          errors << "JournalEntry #{je.id} (#{je.entry_date}) has no lines"
          next
        end

        debits  = lines.select  { |l| l.side == "debit"  }.sum { |l| l.amount.to_d }
        credits = lines.select  { |l| l.side == "credit" }.sum { |l| l.amount.to_d }
        if (debits - credits).abs > 0.01
          errors << "JournalEntry #{je.id} unbalanced: debits=#{debits} credits=#{credits}"
        end

        lines.each do |l|
          errors << "JournalLine #{l.id} missing account" if l.account.nil?
        end
      end

      { errors: errors, checked: checked }
    end
  end
end
