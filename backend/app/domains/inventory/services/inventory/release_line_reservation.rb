module Inventory
  class ReleaseLineReservation
    def self.call(order_line_item, quantity:)
      new(order_line_item, quantity: quantity).call
    end

    def initialize(order_line_item, quantity:)
      @order_line_item = order_line_item
      @quantity = quantity.to_i
      @affected_stock_item_ids = []
    end

    def call
      return @order_line_item if @quantity <= 0

      @order_line_item.stock_reservations.active.each { |reservation| @affected_stock_item_ids << reservation.stock_item_id }
      ReservationsCommand.release(order_line_item: @order_line_item, quantity: @quantity)

      @affected_stock_item_ids.uniq.each do |stock_item_id|
        stock_item = StockItem.find_by(id: stock_item_id)
        Reservations::RecountStockItem.call(stock_item) if stock_item
      end

      @order_line_item.reload
    end
  end
end