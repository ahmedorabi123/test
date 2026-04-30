class OrderLineItem < ApplicationRecord
  belongs_to :order, inverse_of: :line_items
  belongs_to :variant, optional: true

  validates :title,    presence: true
  validates :quantity, numericality: { greater_than: 0 }
  validates :price,    numericality: { greater_than_or_equal_to: 0 }

  before_validation :calculate_line_total

  private

  def calculate_line_total
    return if line_total.present? && line_total.positive? && !quantity_changed? && !price_changed? && !total_discount_changed?
    gross = price.to_d * quantity.to_i
    self.line_total = gross - total_discount.to_d
  end
end
