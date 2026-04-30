class StockItem < ApplicationRecord
  belongs_to :variant,   inverse_of: :stock_items
  belongs_to :warehouse, inverse_of: :stock_items

  has_many :stock_movements, dependent: :restrict_with_error

  validates :quantity_on_hand,     numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :quantity_reserved,    numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :low_stock_threshold,  numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :variant_id, uniqueness: { scope: :warehouse_id }

  scope :low_stock, -> {
    where("quantity_on_hand - quantity_reserved <= low_stock_threshold")
  }

  def available
    [quantity_on_hand - quantity_reserved, 0].max
  end

  def low_stock?
    available <= low_stock_threshold
  end
end
