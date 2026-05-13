class Refund < ApplicationRecord
  include Shopify::Origin

  STATUSES = %w[draft approved processed cancelled].freeze
  KINDS = %w[shopify manual estebdal exchange].freeze

  shopify_origin_via :shopify_refund_id

  belongs_to :order, inverse_of: :refunds
  has_many   :refund_line_items, dependent: :destroy, inverse_of: :refund

  accepts_nested_attributes_for :refund_line_items, allow_destroy: true

  validates :amount, numericality: { greater_than_or_equal_to: 0 }
  validates :status, inclusion: { in: STATUSES }, allow_blank: true
  validates :kind, inclusion: { in: KINDS }, allow_blank: true

  scope :with_restock, -> { where(restock: true) }
  scope :manual_source, -> { where(shopify_refund_id: nil) }

  def partial?
    amount.to_d > 0 && order && amount.to_d < order.total_price.to_d
  end

  def full?
    order && amount.to_d >= order.total_price.to_d
  end

  def processed?
    status.to_s == "processed"
  end
end
