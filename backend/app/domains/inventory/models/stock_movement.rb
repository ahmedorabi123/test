class StockMovement < ApplicationRecord
  REASONS = %w[received fulfilled returned adjusted shopify_sync transfer initial_stock manufactured consumed showroom_sale refund_restock].freeze

  belongs_to :stock_item, inverse_of: :stock_movements

  validates :delta,  presence: true, numericality: { only_integer: true, other_than: 0 }
  validates :reason, inclusion: { in: REASONS }
  validates :snapshot_before, :snapshot_after, numericality: { only_integer: true }

  after_initialize :readonly_once_persisted

  private

  def readonly_once_persisted
    freeze if persisted?
  end
end
