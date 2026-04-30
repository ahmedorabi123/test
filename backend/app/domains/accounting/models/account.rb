class Account < ApplicationRecord
  TYPES   = %w[asset liability equity revenue expense].freeze
  SIDES   = %w[debit credit].freeze

  belongs_to :parent, class_name: "Account", optional: true
  has_many   :children, class_name: "Account", foreign_key: :parent_id, dependent: :restrict_with_error
  has_many   :journal_lines

  validates :code,         presence: true, uniqueness: true
  validates :name,         presence: true
  validates :account_type, inclusion: { in: TYPES }
  validates :normal_side,  inclusion: { in: SIDES }

  scope :active,      -> { where(active: true) }
  scope :assets,      -> { where(account_type: "asset") }
  scope :liabilities, -> { where(account_type: "liability") }
  scope :equity,      -> { where(account_type: "equity") }
  scope :revenue,     -> { where(account_type: "revenue") }
  scope :expenses,    -> { where(account_type: "expense") }

  # Balance = sum of lines on normal side minus opposite side
  def balance
    debits  = journal_lines.where(side: "debit").sum(:amount)
    credits = journal_lines.where(side: "credit").sum(:amount)
    normal_side == "debit" ? debits - credits : credits - debits
  end
end
