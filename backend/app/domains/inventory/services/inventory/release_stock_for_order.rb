module Inventory
  # Releases reserved stock for an order by decrementing quantity_reserved on
  # each relevant StockItem. Called when an order is fulfilled or cancelled.
  #
  # When fulfilling: stock is already deducted from on_hand by FulfillmentUpserter;
  # we just zero out the reservation for fulfilled line items.
  # When cancelling: reservation is released back to available (no on_hand change).
  # Idempotent — safe to call multiple times.
  class ReleaseStockForOrder
    def self.call(order)
      new(order).call
    end

    def initialize(order)
      @order = order
    end

    def call
      ReleaseOrderReservations.call(@order)
    end
  end
end
