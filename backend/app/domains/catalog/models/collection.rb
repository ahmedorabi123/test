class Collection < ApplicationRecord
  KINDS = %w[custom smart].freeze
  SOURCES = %w[manual shopify].freeze

  has_many :collection_products, dependent: :destroy
  has_many :products, through: :collection_products

  validates :title,  presence: true
  validates :handle, presence: true, uniqueness: { case_sensitive: false }
  validates :kind,   inclusion: { in: KINDS }
  validates :source, inclusion: { in: SOURCES }

  scope :custom,       -> { where(kind: "custom") }
  scope :smart,        -> { where(kind: "smart") }
  scope :published,    -> { where.not(published_at: nil) }
  scope :from_shopify, -> { where.not(shopify_collection_id: nil) }

  before_validation :derive_handle, if: -> { handle.blank? && title.present? }

  def custom? = kind == "custom"
  def smart?  = kind == "smart"

  private

  def derive_handle
    self.handle = title.to_s.downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-+|-+\z/, "")
  end
end
