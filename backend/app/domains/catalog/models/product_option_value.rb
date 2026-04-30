class ProductOptionValue < ApplicationRecord
  belongs_to :product_option

  validates :value, presence: true,
                    uniqueness: { scope: :product_option_id, case_sensitive: false }
end
