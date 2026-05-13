class StockTransfer < ApplicationRecord
  STATUSES = %w[draft posted cancelled].freeze
  REASONS  = %w[transfer restock showroom_prep return rebalance other].freeze

  belongs_to :from_warehouse, class_name: "Warehouse"
  belongs_to :to_warehouse,   class_name: "Warehouse"
  belongs_to :posted_by_user,  class_name: "User", optional: true
  belongs_to :created_by_user, class_name: "User", optional: true

  has_many :stock_transfer_lines, dependent: :destroy
  has_many :variants, through: :stock_transfer_lines

  validates :reference, presence: true, uniqueness: { case_sensitive: false }
  validates :status, inclusion: { in: STATUSES }
  validates :reason, presence: true
  validate  :warehouses_differ

  scope :posted,    -> { where(status: "posted") }
  scope :recent,    -> { order(posted_at: :desc, created_at: :desc) }

  # Generate the next sequential reference per year (TR-YYYY-NNNN).
  # Caller must take a row-level/advisory lock or rely on uniqueness retry.
  def self.next_reference(year: Date.current.year)
    last = where("reference LIKE ?", "TR-#{year}-%").order(reference: :desc).first
    seq  = last ? last.reference.split("-").last.to_i + 1 : 1
    format("TR-%d-%04d", year, seq)
  end

  def total_quantity
    stock_transfer_lines.sum(:quantity)
  end

  def posted?    = status == "posted"
  def draft?     = status == "draft"
  def cancelled? = status == "cancelled"

  private

  def warehouses_differ
    return if from_warehouse_id.blank? || to_warehouse_id.blank?
    errors.add(:to_warehouse_id, "must differ from source") if from_warehouse_id == to_warehouse_id
  end
end
