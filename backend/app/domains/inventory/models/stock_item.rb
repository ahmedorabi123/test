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
  validates :shopify_quantity_on_hand, :shopify_quantity_committed,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
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

  def shopify_tracked?
    warehouse&.shopify_origin? && variant&.shopify_inventory_item_id.present?
  end

  def shopify_available
    return nil unless shopify_tracked? && shopify_quantity_on_hand.present?

    [shopify_quantity_on_hand.to_i - shopify_quantity_committed.to_i, 0].max
  end

  def shopify_divergence
    return nil unless shopify_tracked? && shopify_quantity_on_hand.present?

    on_hand_delta = quantity_on_hand.to_i - shopify_quantity_on_hand.to_i
    committed_delta = if shopify_quantity_committed.nil?
      nil
    else
      quantity_reserved.to_i - shopify_quantity_committed.to_i
    end
    return nil if on_hand_delta.zero? && committed_delta.to_i.zero?

    {
      on_hand_delta: on_hand_delta,
      committed_delta: committed_delta,
      system_on_hand: quantity_on_hand.to_i,
      shopify_on_hand: shopify_quantity_on_hand.to_i,
      system_committed: quantity_reserved.to_i,
      shopify_committed: shopify_quantity_committed
    }
  end

  def shopify_origin?
    super || warehouse&.shopify_origin?
  end
end
