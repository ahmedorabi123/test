class StockTransferLine < ApplicationRecord
  belongs_to :stock_transfer
  belongs_to :variant

  validates :quantity, numericality: { only_integer: true, greater_than: 0 }
  validates :variant_id, uniqueness: { scope: :stock_transfer_id,
                                       message: "already on this transfer" }
end
