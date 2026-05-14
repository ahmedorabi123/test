class Order < ApplicationRecord
  include Shopify::Origin

  STATUSES            = %w[pending processing fulfilled cancelled refunded].freeze
  FINANCIAL_STATUSES  = %w[pending authorized paid partially_refunded refunded voided].freeze
  FULFILLMENT_STATUSES = %w[partial fulfilled].freeze
  SOURCES             = %w[manual shopify showroom].freeze

  shopify_origin_via :shopify_order_id,
    read_only_except: %i[status financial_status fulfillment_status notes last_delivery_status cancelled_at updated_at]

  has_many :line_items, class_name: "OrderLineItem", dependent: :destroy, inverse_of: :order
  has_many :fulfillments, dependent: :destroy, inverse_of: :order
  has_many :refunds,      dependent: :destroy, inverse_of: :order
  has_many :stock_reservations, through: :line_items
  belongs_to :customer, optional: true, inverse_of: :orders

  accepts_nested_attributes_for :line_items, allow_destroy: true

  validates :order_number, presence: true, uniqueness: { case_sensitive: false }
  validates :status,           inclusion: { in: STATUSES }
  validates :financial_status, inclusion: { in: FINANCIAL_STATUSES }
  validates :fulfillment_status, inclusion: { in: FULFILLMENT_STATUSES, allow_nil: true }
  validates :source,           inclusion: { in: SOURCES }
  validates :currency,         presence: true, length: { is: 3 }
  validates :placed_at,        presence: true

  scope :recent,        -> { order(placed_at: :desc) }
  scope :from_shopify,  -> { where.not(shopify_order_id: nil) }
  scope :last_30_days,  -> { where("placed_at >= ?", 30.days.ago) }
  scope :with_status,   ->(s) { where(status: s) if s.present? }

  before_validation :assign_order_number, on: :create, if: -> { order_number.blank? }

  private

  def assign_order_number
    self.order_number = "SO-#{Time.current.strftime('%Y%m')}-#{SecureRandom.hex(4).upcase}"
  end
end
