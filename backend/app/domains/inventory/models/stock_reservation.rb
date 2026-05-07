class StockReservation < ApplicationRecord
  STATUSES = %w[active released consumed].freeze

  belongs_to :order_line_item, inverse_of: :stock_reservations
  belongs_to :stock_item,      inverse_of: :stock_reservations

  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :status, inclusion: { in: STATUSES }

  scope :active,   -> { where(status: "active") }
  scope :released, -> { where(status: "released") }
  scope :consumed, -> { where(status: "consumed") }
end