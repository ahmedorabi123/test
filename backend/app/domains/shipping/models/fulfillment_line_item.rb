class FulfillmentLineItem < ApplicationRecord
  belongs_to :fulfillment,     inverse_of: :fulfillment_line_items
  belongs_to :order_line_item, optional: true

  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
end
