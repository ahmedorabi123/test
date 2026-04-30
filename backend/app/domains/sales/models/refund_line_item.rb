class RefundLineItem < ApplicationRecord
  RESTOCK_TYPES = %w[return cancel no_restock].freeze

  belongs_to :refund,          inverse_of: :refund_line_items
  belongs_to :order_line_item, optional: true

  validates :quantity, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :restock_type, inclusion: { in: RESTOCK_TYPES, allow_nil: true }
end
