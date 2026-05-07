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

      remaining = @quantity
      ActiveRecord::Base.transaction do
        @order_line_item.stock_reservations.active.lock.order(:created_at).each do |reservation|
          break if remaining <= 0

          @affected_stock_item_ids << reservation.stock_item_id
          if remaining >= reservation.quantity
            remaining -= reservation.quantity
            reservation.update!(status: "released")
          else
            reservation.update!(quantity: reservation.quantity - remaining)
            remaining = 0
          end
        end
      end

      @affected_stock_item_ids.uniq.each do |stock_item_id|
        stock_item = StockItem.find_by(id: stock_item_id)
        Reservations::RecountStockItem.call(stock_item) if stock_item
      end

      @order_line_item.reload
    end
  end
end