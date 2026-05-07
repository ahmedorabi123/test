class Supplier < ApplicationRecord
  STATUSES = %w[active on_hold inactive].freeze

  has_many :purchase_orders, dependent: :restrict_with_error

  validates :name, presence: true
  validates :supplier_code, uniqueness: { case_sensitive: false }, allow_blank: true
  validates :lead_time_days,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :status, inclusion: { in: STATUSES }
  validates :currency, presence: true, length: { is: 3 }

  before_validation :assign_supplier_code, if: -> { supplier_code.blank? && name.present? }

  scope :active, -> { where(status: "active") }
  scope :recent, -> { order(created_at: :desc) }

  private

  def assign_supplier_code
    base = name.to_s.parameterize(separator: "").upcase.first(8).presence || "SUP"
    candidate = base
    suffix = 1
    while Supplier.where.not(id: id).exists?(supplier_code: candidate)
      suffix += 1
      candidate = "#{base}#{suffix}"
    end
    self.supplier_code = candidate
  end
end
