class Fulfillment < ApplicationRecord
  STATUSES = %w[pending open success cancelled error failure].freeze

  belongs_to :order, inverse_of: :fulfillments
  has_many   :fulfillment_line_items, dependent: :destroy, inverse_of: :fulfillment

  accepts_nested_attributes_for :fulfillment_line_items, allow_destroy: true

  validates :status, inclusion: { in: STATUSES }

  scope :successful, -> { where(status: "success") }
  scope :via_bosta,  -> { where("LOWER(tracking_company) = 'bosta'") }

  def shopify_linked?
    shopify_fulfillment_id.present?
  end

  def bosta?
    tracking_company.to_s.downcase == "bosta"
  end
end
