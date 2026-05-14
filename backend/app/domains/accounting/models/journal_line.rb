class JournalLine < ApplicationRecord
  SIDES = %w[debit credit].freeze

  belongs_to :journal_entry
  belongs_to :account
  # Optional link to a material supplier for fabric/material purchases entered
  # manually in accounting (Phase 1). Factory POs do not post journals, so the
  # supplier_id linkage is only meaningful for material suppliers today.
  belongs_to :supplier, optional: true

  validates :side,   inclusion: { in: SIDES }
  validates :amount, numericality: { greater_than: 0 }
end
