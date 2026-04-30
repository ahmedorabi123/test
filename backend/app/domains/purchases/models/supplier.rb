class Supplier < ApplicationRecord
  STATUSES = %w[active inactive].freeze

  has_many :purchase_orders, dependent: :restrict_with_error

  validates :name, presence: true
  validates :status, inclusion: { in: STATUSES }
  validates :currency, presence: true, length: { is: 3 }

  scope :active, -> { where(status: "active") }
  scope :recent, -> { order(created_at: :desc) }
end
