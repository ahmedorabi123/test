module Inventory
  class ConsumeOrderLineReservations
    def self.call(order, actor: nil)
      new(order, actor: actor).call
    end

    def initialize(order, actor: nil)
      @order = order
      @actor = actor
    end

    def call
      stock_items = []

      ActiveRecord::Base.transaction do
        @order.line_items.includes(:stock_reservations).each do |line_item|
          stock_item = consume_line!(line_item)
          stock_items << stock_item if stock_item
        end
        @order.update!(fulfillment_status: "fulfilled")
      end

      stock_items.compact.uniq.each { |stock_item| Reservations::RecountStockItem.call(stock_item) }
      @order.reload
    end

    private

    def consume_line!(line_item)
      line_item.lock!
      return nil if already_moved?(line_item)

      remaining = [line_item.quantity.to_i - line_item.fulfilled_quantity.to_i, 0].max
      return nil if remaining <= 0

      reservation = line_item.stock_reservations.active.lock.first
      stock_item = reservation&.stock_item || fallback_stock_item(line_item)
      return nil unless stock_item

      stock_item.with_lock do
        Inventory::ReservationsCommand.consume(
          order_line_item: line_item,
          quantity: remaining,
          stock_item: reservation&.stock_item
        ) if reservation

        Inventory::WriteMovement.call(
          stock_item: stock_item,
          delta: -remaining,
          reason: "fulfilled",
          reference: line_item
        )

        Inventory::ConsumeCostLayers.call(
          stock_item: stock_item,
          quantity: remaining,
          reference: line_item
        )

        line_item.update!(fulfilled_quantity: line_item.fulfilled_quantity.to_i + remaining)
      end

      stock_item
    end

    def already_moved?(line_item)
      StockMovement.exists?(
        movement_scope: "system",
        reference_type: line_item.class.name,
        reference_id: line_item.id.to_s,
        reason: "fulfilled"
      )
    end

    def fallback_stock_item(line_item)
      variant = line_item.variant
      warehouse = WarehouseResolver.for_order(@order)
      return nil unless variant && warehouse

      StockItem.find_or_create_by!(variant: variant, warehouse: warehouse) do |stock_item|
        stock_item.quantity_on_hand = 0
      end
    end
  end
end
