class PurchaseOrderLineItem < ApplicationRecord
  belongs_to :purchase_order, inverse_of: :line_items
  belongs_to :variant, optional: true

  validates :quantity_ordered,  numericality: { greater_than_or_equal_to: 0 }
  validates :quantity_received, numericality: { greater_than_or_equal_to: 0 }

  def remaining
    [quantity_ordered - quantity_received, 0].max
  end
end
