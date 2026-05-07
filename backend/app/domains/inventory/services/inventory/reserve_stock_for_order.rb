module Inventory
  # Reserves stock for an order by incrementing quantity_reserved on each
  # relevant StockItem. Called when an order transitions to open/unfulfilled
  # status (e.g., Shopify order created/confirmed).
  #
  # Looks up stock items by variant_id across a preferred warehouse (via
  # order location_id) then falls back to any warehouse with stock.
  # Idempotent — safe to call multiple times for the same order.
  class ReserveStockForOrder
    def self.call(order)
      new(order).call
    end

    def initialize(order)
      @order = order
    end

    def call
      SyncOrderReservations.call(@order)
    end
  end
end
