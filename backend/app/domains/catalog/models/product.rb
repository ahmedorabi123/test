class Product < ApplicationRecord
  include Shopify::Origin

  STATUSES = %w[active draft archived].freeze
  PUBLISHED_SCOPES = %w[web global].freeze
  SOURCES = %w[manual shopify].freeze

  shopify_origin_via :shopify_product_id

  has_many :variants, -> { order(:position) }, dependent: :destroy, inverse_of: :product
  has_many :product_options, -> { order(:position) }, dependent: :destroy, inverse_of: :product
  has_many :product_images,  -> { order(:position) }, dependent: :destroy, inverse_of: :product
  has_many :collection_products, dependent: :destroy
  has_many :collections, through: :collection_products

  has_many_attached :uploaded_images

  accepts_nested_attributes_for :variants,        allow_destroy: true
  accepts_nested_attributes_for :product_options, allow_destroy: true
  accepts_nested_attributes_for :product_images,  allow_destroy: true

  validates :title,  presence: true
  validates :handle, presence: true, uniqueness: { case_sensitive: false }
  validates :status, inclusion: { in: STATUSES }
  validates :published_scope, inclusion: { in: PUBLISHED_SCOPES }, allow_blank: true
  validates :source, inclusion: { in: SOURCES }

  scope :active,    -> { where(status: "active") }
  scope :from_shopify, -> { where.not(shopify_product_id: nil) }

  before_validation :derive_handle_from_title, if: -> { handle.blank? && title.present? }
  before_save :coerce_tags

  private

  def derive_handle_from_title
    self.handle = title.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
  end

  def coerce_tags
    self.tags = case tags
                when Array  then tags.map(&:to_s).map(&:strip).reject(&:blank?).uniq
                when String then tags.split(",").map(&:strip).reject(&:blank?).uniq
                else []
                end
  end
end
