module Inventory
  class ReleaseOrderReservations
    def self.call(order)
      new(order).call
    end

    def initialize(order)
      @order = order
      @affected_stock_item_ids = []
    end

    def call
      ActiveRecord::Base.transaction do
        @order.line_items.includes(:stock_reservations).each do |line_item|
          line_item.stock_reservations.active.each { |reservation| @affected_stock_item_ids << reservation.stock_item_id }
          ReservationsCommand.release(order_line_item: line_item)
        end
      end

      recount_affected!
      @order.reload
    end

    private

    def recount_affected!
      @affected_stock_item_ids.uniq.each do |stock_item_id|
        stock_item = StockItem.find_by(id: stock_item_id)
        Reservations::RecountStockItem.call(stock_item) if stock_item
      end
    end
  end
end