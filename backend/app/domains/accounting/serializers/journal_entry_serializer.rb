class JournalEntrySerializer
  def self.call(entry, include_lines: false)
    h = {
      id:            entry.id,
      entry_date:    entry.entry_date,
      description:   entry.description,
      status:        entry.status,
      currency:      entry.currency,
      entry_type:    entry.entry_type,
      source_type:   entry.source_type,
      source_id:     entry.source_id,
      reversal_of_id: entry.reversal_of_id,
      is_reversal:   entry.reversal_of_id.present?,
      total_debits:  entry.journal_lines.select { |l| l.side == "debit" }.sum { |l| l.amount.to_f },
      total_credits: entry.journal_lines.select { |l| l.side == "credit" }.sum { |l| l.amount.to_f },
      created_at:    entry.created_at
    }
    if include_lines
      h[:lines] = entry.journal_lines.map do |l|
        {
          id:            l.id,
          account_code:  l.account.code,
          account_name:  l.account.name,
          side:          l.side,
          amount:        l.amount.to_f,
          currency:      l.currency,
          description:   l.description,
          supplier_id:   l.supplier_id,
          supplier_code: l.supplier&.supplier_code,
          supplier_name: l.supplier&.name
        }
      end
    end
    h
  end
end
