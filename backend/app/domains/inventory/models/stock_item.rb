class StockItem < ApplicationRecord
  include Shopify::Origin

  shopify_origin_via :shopify_inventory_level_id

  belongs_to :variant,   inverse_of: :stock_items
  belongs_to :warehouse, inverse_of: :stock_items

  has_many :stock_movements, dependent: :restrict_with_error
  has_many :stock_reservations, dependent: :restrict_with_error

  validates :quantity_on_hand,      numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :quantity_reserved,     numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :quantity_unavailable,  numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :low_stock_threshold,   numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :variant_id, uniqueness: { scope: :warehouse_id }

  scope :low_stock, -> {
    where("quantity_on_hand - quantity_reserved - quantity_unavailable <= low_stock_threshold")
  }

  def available
    [quantity_on_hand - quantity_reserved - quantity_unavailable, 0].max
  end

  def raw_available
    quantity_on_hand - quantity_reserved - quantity_unavailable
  end

  def low_stock?
    available <= low_stock_threshold
  end

  def shopify_origin?
    super || warehouse&.shopify_origin? || variant&.shopify_origin? || variant&.product&.shopify_origin?
  end
end
