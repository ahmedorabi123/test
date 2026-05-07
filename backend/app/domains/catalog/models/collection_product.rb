class CollectionProduct < ApplicationRecord
  belongs_to :collection
  belongs_to :product

  validates :collection_id, uniqueness: { scope: :product_id }
end
