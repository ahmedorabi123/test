class StockCostLayer < ApplicationRecord
  belongs_to :stock_item
  belongs_to :variant
  belongs_to :warehouse

  validates :quantity_received, numericality: { only_integer: true, greater_than: 0 }
  validates :qty_remaining, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :unit_cost, numericality: { greater_than_or_equal_to: 0 }
  validates :source_type, :source_id, :received_at, presence: true

  scope :open, -> { where("qty_remaining > 0") }
  scope :fifo, -> { order(:received_at, :created_at, :id) }
end