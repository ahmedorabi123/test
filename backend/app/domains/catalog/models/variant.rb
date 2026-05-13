class Variant < ApplicationRecord
  include Shopify::Origin

  INVENTORY_POLICIES = %w[deny continue].freeze
  WEIGHT_UNITS       = %w[kg g lb oz].freeze

  shopify_origin_via :shopify_variant_id, read_only_except: %i[cost cost_per_item updated_at]

  belongs_to :product, inverse_of: :variants
  has_many :stock_items, dependent: :destroy
  has_many :product_images, dependent: :nullify

  accepts_nested_attributes_for :stock_items, allow_destroy: false, reject_if: :all_blank

  validates :title, presence: true
  validates :price, numericality: { greater_than_or_equal_to: 0 }
  validates :cost, :last_purchase_cost,
            numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :sku, uniqueness: { case_sensitive: false }, allow_blank: true
  validates :inventory_policy, inclusion: { in: INVENTORY_POLICIES }, allow_blank: true
  validates :weight_unit,      inclusion: { in: WEIGHT_UNITS },      allow_blank: true

  scope :from_shopify, -> { where.not(shopify_variant_id: nil) }

  after_commit :provision_stock_items, on: :create

  # Convenience: return the option1/2/3 triple for display.
  def option_values
    [ option1, option2, option3 ].compact
  end

  private

  def provision_stock_items
    Inventory::ProvisionStockItemsJob.perform_later(id)
  end
end
