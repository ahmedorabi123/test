class ProductOption < ApplicationRecord
  belongs_to :product
  has_many :product_option_values, -> { order(:position) }, dependent: :destroy

  validates :name, presence: true, uniqueness: { scope: :product_id, case_sensitive: false }
end
