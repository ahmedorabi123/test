module Inventory
  module Reservations
    class RecountStockItem
      def self.call(stock_item)
        new(stock_item).call
      end

      def initialize(stock_item)
        @stock_item = stock_item
      end

      def call
        StockItem.transaction do
          stock_item = StockItem.lock.find(@stock_item.id)
          quantity = StockReservation.active.where(stock_item_id: stock_item.id).sum(:quantity)
          ::Shopify::Origin.without_read_only do
            stock_item.update!(quantity_reserved: quantity)
          end
          stock_item
        end
      end
    end
  end
end