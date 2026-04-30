class ProductionOrder < ApplicationRecord
  self.table_name = "production_orders"

  STATUSES = %w[draft in_progress completed cancelled].freeze
  MODES    = %w[single staged].freeze

  belongs_to :parent_variant, class_name: "Variant",
                              foreign_key: :parent_variant_id
  belongs_to :warehouse
  belongs_to :created_by, class_name: "User", optional: true

  has_many :production_stages, -> { order(:position) },
           dependent: :destroy

  validates :number,          presence: true, uniqueness: true
  validates :quantity,        numericality: { greater_than: 0, only_integer: true }
  validates :status,          inclusion: { in: STATUSES }
  validates :production_mode, inclusion: { in: MODES }

  before_validation :set_number, on: :create

  def staged?
    production_mode == "staged"
  end

  # Total cost = sum of stage unit_costs * quantity (or fall back to po.unit_cost * qty)
  def computed_unit_cost
    return unit_cost.to_d if production_stages.empty?
    production_stages.sum(:unit_cost).to_d
  end

  def total_cost
    computed_unit_cost * quantity
  end

  private

  def set_number
    return if number.present?
    self.number = "PRD-#{SecureRandom.hex(4).upcase}"
  end
end

