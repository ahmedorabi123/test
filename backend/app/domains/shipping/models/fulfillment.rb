class Fulfillment < ApplicationRecord
  include Shopify::Origin

  STATUSES = %w[pending open success cancelled error failure].freeze
  DELIVERY_STATUSES = %w[pending label_purchased confirmed in_transit out_for_delivery attempted_delivery ready_for_pickup picked_up delivered failed failure].freeze

  # Map Shopify's shipment_status vocabulary to a value our store accepts.
  # Shopify uses values like "failure" and "out_for_delivery" that legacy
  # tests/code didn't allow. We accept the raw Shopify values directly so we
  # don't lose information; only fully unknown values are normalised.
  SHOPIFY_DELIVERY_STATUS_ALIASES = {
    "label_printed"  => "label_purchased",
    "in transit"     => "in_transit",
    "out for delivery" => "out_for_delivery"
  }.freeze

  def self.normalize_delivery_status(raw)
    return nil if raw.blank?
    v = raw.to_s.downcase.strip
    v = SHOPIFY_DELIVERY_STATUS_ALIASES[v] || v
    DELIVERY_STATUSES.include?(v) ? v : nil
  end

  shopify_origin_via :shopify_fulfillment_id,
    read_only_except: %i[delivery_status in_transit_at delivered_at notes updated_at]

  belongs_to :order, inverse_of: :fulfillments
  has_many   :fulfillment_line_items, dependent: :destroy, inverse_of: :fulfillment
  has_many   :shipment_events, dependent: :destroy, inverse_of: :fulfillment

  accepts_nested_attributes_for :fulfillment_line_items, allow_destroy: true

  validates :status, inclusion: { in: STATUSES }
  validates :delivery_status, inclusion: { in: DELIVERY_STATUSES }, allow_nil: true

  before_validation :coerce_tags
  after_save        :sync_order_last_delivery_status, if: :saved_change_to_delivery_status?
  after_destroy     :sync_order_last_delivery_status

  scope :successful, -> { where(status: "success") }
  scope :via_bosta,  -> { where("LOWER(tracking_company) = 'bosta'") }

  def bosta?
    tracking_company.to_s.downcase == "bosta"
  end

  private

  def coerce_tags
    self.tags = case tags
    when Array then tags.map(&:to_s).map(&:strip).reject(&:blank?).uniq
    when String then tags.split(",").map(&:strip).reject(&:blank?).uniq
    else []
    end if respond_to?(:tags=)
  end

  # Denormalise the latest fulfillment's delivery_status onto the parent order
  # so the orders list can sort/filter by it without an N+1 lookup.
  def sync_order_last_delivery_status
    return unless order_id

    latest = Fulfillment.where(order_id: order_id)
                        .order(created_at: :desc)
                        .limit(1)
                        .pick(:delivery_status)
    Order.where(id: order_id).update_all(last_delivery_status: latest)
  end
end
