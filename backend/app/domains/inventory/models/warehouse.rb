class Warehouse < ApplicationRecord
  include Shopify::Origin

  CODES_FORMAT = /\A[A-Z0-9\-]+\z/
  KINDS        = %w[own consignment transit].freeze

  shopify_origin_via :shopify_location_id

  has_many :stock_items, dependent: :destroy

  validates :name, presence: true
  validates :code, presence: true,
                   uniqueness: { case_sensitive: false },
                   format: { with: CODES_FORMAT, message: "must be uppercase alphanumeric with dashes" }
  validates :kind, inclusion: { in: KINDS }

  before_validation :upcase_code
  before_validation :default_kind

  scope :active,       -> { where(active: true) }
  scope :own,          -> { where(kind: "own") }
  scope :consignment,  -> { where(kind: "consignment") }

  private

  def upcase_code
    self.code = code.to_s.upcase.strip
  end

  def default_kind
    self.kind = "own" if kind.blank?
  end
end
