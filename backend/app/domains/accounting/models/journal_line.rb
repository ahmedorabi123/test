class JournalLine < ApplicationRecord
  SIDES = %w[debit credit].freeze

  belongs_to :journal_entry
  belongs_to :account

  validates :side,   inclusion: { in: SIDES }
  validates :amount, numericality: { greater_than: 0 }
end
