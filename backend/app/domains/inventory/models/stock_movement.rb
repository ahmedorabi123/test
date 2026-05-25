class StockMovement < ApplicationRecord
  REASONS = %w[
    received fulfilled returned adjusted shopify_sync transfer initial_stock
    manufactured consumed showroom_sale refund_restock reserved
    reservation_released reservation_consumed shopify_mirror_order_committed
    shopify_mirror_order_consumed shopify_mirror_order_released shopify_mirror_reconcile
  ].freeze
  MOVEMENT_SCOPES = %w[system shopify_mirror].freeze

  belongs_to :stock_item, inverse_of: :stock_movements

  validates :delta,  presence: true, numericality: { only_integer: true }
  validates :reason, inclusion: { in: REASONS }
  validates :movement_scope, inclusion: { in: MOVEMENT_SCOPES }
  validates :snapshot_before, :snapshot_after, numericality: { only_integer: true }

  after_initialize :readonly_once_persisted

  private

  def readonly_once_persisted
    freeze if persisted?
  end
end
