class JournalEntry < ApplicationRecord
  STATUSES    = %w[draft posted reversed].freeze
  ENTRY_TYPES = %w[sale refund purchase adjustment manual].freeze

  belongs_to :reversal_of, class_name: "JournalEntry", optional: true
  has_many   :journal_lines, dependent: :destroy

  validates :entry_date,   presence: true
  validates :description,  presence: true
  validates :status,       inclusion: { in: STATUSES }
  validates :entry_type,   inclusion: { in: ENTRY_TYPES }, allow_nil: true
  validate  :balanced_lines, if: -> { status == "posted" && journal_lines.any? }

  scope :posted,   -> { where(status: "posted") }
  scope :reversed, -> { where(status: "reversed") }
  scope :for_date, ->(d) { where(entry_date: d) }
  scope :between,  ->(from, to) { where(entry_date: from..to) }

  # Free-text ILIKE on the entry description and any line description.
  scope :search_text, ->(q) {
    next all if q.blank?
    term = "%#{ActiveRecord::Base.sanitize_sql_like(q.to_s)}%"
    where(
      "journal_entries.description ILIKE :q OR EXISTS (" \
        "SELECT 1 FROM journal_lines jl WHERE jl.journal_entry_id = journal_entries.id " \
        "AND jl.description ILIKE :q)",
      q: term
    )
  }

  # Restrict to entries that touch at least one line in the given amount range.
  scope :with_amount_between, ->(min, max) {
    next all if min.nil? && max.nil?
    sub = JournalLine.select(:journal_entry_id)
    sub = sub.where("amount >= ?", min) if min.present?
    sub = sub.where("amount <= ?", max) if max.present?
    where(id: sub)
  }

  # Restrict to entries that post to an account whose code starts with the given prefix.
  scope :with_account_code, ->(code) {
    next all if code.blank?
    where(id: JournalLine.joins(:account)
      .where("LOWER(accounts.code) LIKE ?", "#{code.to_s.downcase}%")
      .select(:journal_entry_id))
  }

  # Post a new journal entry atomically.
  # lines_attrs: array of { account_code:, side:, amount:, description: }
  def self.post!(attrs, lines_attrs)
    transaction do
      entry = new(attrs.merge(status: "posted"))
      lines_attrs.each do |la|
        account = Account.find_by!(code: la[:account_code])
        entry.journal_lines.build(
          account:     account,
          side:        la.fetch(:side),
          amount:      la.fetch(:amount).to_d,
          currency:    la[:currency] || entry.currency,
          description: la[:description],
          supplier_id: la[:supplier_id]
        )
      end
      entry.save!
      entry
    end
  end

  # Reverse a posted entry (creates an opposite entry).
  def reverse!(description: "Reversal of #{self.description}")
    raise "Can only reverse a posted entry" unless status == "posted"
    transaction do
      reversal = self.class.post!(
        {
          entry_date:        Date.current,
          description:       description,
          currency:          currency,
          source_type:       source_type,
          source_id:         source_id,
          entry_type:        entry_type,
          reversal_of_id:    id
        },
        journal_lines.map { |l|
          { account_code: l.account.code, side: l.side == "debit" ? "credit" : "debit",
            amount: l.amount, currency: l.currency, description: "Reversal: #{l.description}" }
        }
      )
      update!(status: "reversed")
      reversal
    end
  end

  def total_debits
    journal_lines.select { |l| l.side == "debit" }.sum(&:amount)
  end

  def total_credits
    journal_lines.select { |l| l.side == "credit" }.sum(&:amount)
  end

  private

  def balanced_lines
    debits  = journal_lines.reject(&:marked_for_destruction?).select { |l| l.side == "debit" }.sum { |l| l.amount.to_d }
    credits = journal_lines.reject(&:marked_for_destruction?).select { |l| l.side == "credit" }.sum { |l| l.amount.to_d }
    errors.add(:base, "Journal entry is not balanced: debits=#{debits} credits=#{credits}") unless debits == credits
  end
end
