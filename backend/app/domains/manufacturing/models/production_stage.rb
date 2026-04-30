class ProductionStage < ApplicationRecord
  self.table_name = "production_stages"

  STATUSES = %w[pending in_progress completed skipped].freeze

  belongs_to :production_order
  belongs_to :supplier, optional: true

  validates :name,     presence: true
  validates :status,   inclusion: { in: STATUSES }
  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }

  scope :ordered, -> { order(:position) }

  def start!
    update!(status: "in_progress", started_at: started_at || Time.current)
  end

  def complete!
    update!(status: "completed", completed_at: Time.current)
  end
end
