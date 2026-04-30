class Variant < ApplicationRecord
  INVENTORY_POLICIES = %w[deny continue].freeze
  WEIGHT_UNITS       = %w[kg g lb oz].freeze

  belongs_to :product, inverse_of: :variants
  has_many :stock_items, dependent: :destroy
  has_many :product_images, dependent: :nullify

  validates :title, presence: true
  validates :price, numericality: { greater_than_or_equal_to: 0 }
  validates :sku, uniqueness: { case_sensitive: false }, allow_blank: true
  validates :inventory_policy, inclusion: { in: INVENTORY_POLICIES }, allow_blank: true
  validates :weight_unit,      inclusion: { in: WEIGHT_UNITS },      allow_blank: true

  scope :from_shopify, -> { where.not(shopify_variant_id: nil) }

  # Convenience: return the option1/2/3 triple for display.
  def option_values
    [option1, option2, option3].compact
  end
end
