class ProductImage < ApplicationRecord
  belongs_to :product
  belongs_to :variant, optional: true

  validates :src, presence: true
end
