class Refund < ApplicationRecord
  belongs_to :order, inverse_of: :refunds
  has_many   :refund_line_items, dependent: :destroy, inverse_of: :refund

  accepts_nested_attributes_for :refund_line_items, allow_destroy: true

  validates :amount, numericality: { greater_than_or_equal_to: 0 }

  scope :with_restock, -> { where(restock: true) }

  def partial?
    amount.to_d > 0 && order && amount.to_d < order.total_price.to_d
  end

  def full?
    order && amount.to_d >= order.total_price.to_d
  end

  def shopify_linked?
    shopify_refund_id.present?
  end
end
