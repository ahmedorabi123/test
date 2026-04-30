class PurchaseOrder < ApplicationRecord
  STATUSES = %w[draft ordered partial received cancelled].freeze

  belongs_to :supplier, inverse_of: :purchase_orders
  belongs_to :warehouse, optional: true
  belongs_to :created_by, class_name: "User", optional: true
  has_many :line_items, class_name: "PurchaseOrderLineItem",
                        foreign_key: :purchase_order_id,
                        dependent: :destroy, inverse_of: :purchase_order

  accepts_nested_attributes_for :line_items, allow_destroy: true

  validates :po_number, presence: true, uniqueness: { case_sensitive: false }
  validates :status, inclusion: { in: STATUSES }
  validates :currency, presence: true, length: { is: 3 }

  before_validation :assign_po_number, on: :create

  scope :recent, -> { order(created_at: :desc) }
  scope :with_status, ->(s) { where(status: s) if s.present? }

  def fully_received?
    line_items.all? { |li| li.quantity_received >= li.quantity_ordered }
  end

  def any_received?
    line_items.any? { |li| li.quantity_received.positive? }
  end

  private

  def assign_po_number
    return if po_number.present?
    ts = Time.current.strftime("%Y%m")
    self.po_number = "PO-#{ts}-#{SecureRandom.hex(3).upcase}"
  end
end
