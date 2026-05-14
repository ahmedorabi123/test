class ShowroomReversal < ApplicationRecord
  PERIOD_FORMAT = /\A\d{4}-\d{2}(?:-\d{2})?(?:\.\.\d{4}-\d{2}-\d{2})?\z/.freeze

  belongs_to :warehouse
  belongs_to :posted_by_user, class_name: "User", optional: true

  validates :period, presence: true, format: { with: PERIOD_FORMAT }
  validates :idempotency_key, presence: true, uniqueness: true
  validates :warehouse_id, uniqueness: { scope: :period,
                                         message: "already has a reversal for this period" }
  validates :total_amount, numericality: { greater_than_or_equal_to: 0 }

  def self.build_idempotency_key(warehouse_id:, period:)
    "showroom-reversal-#{warehouse_id}-#{period}"
  end
end
