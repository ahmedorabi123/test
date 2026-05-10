module Inventory
  class ConsumeReservation
    def self.call(fulfillment_line_item, warehouse: nil, update_order_status: true)
      new(fulfillment_line_item, warehouse: warehouse, update_order_status: update_order_status).call
    end

    def initialize(fulfillment_line_item, warehouse: nil, update_order_status: true)
      @fulfillment_line_item = fulfillment_line_item
      @warehouse = warehouse
      @update_order_status = update_order_status
    end

    def call
      return nil unless order_line_item

      stock_item = nil

      ActiveRecord::Base.transaction do
        @fulfillment_line_item.lock!
        order_line_item.lock!
        return nil if already_moved?

        reservation = order_line_item.stock_reservations.active.lock.first
        stock_item = reservation&.stock_item || fallback_stock_item
        return nil unless stock_item

        consume_quantity = [ @fulfillment_line_item.quantity.to_i, remaining_quantity ].min
        return nil if consume_quantity <= 0

        stock_item.with_lock do
          if reservation
            if consume_quantity >= reservation.quantity
              reservation.update!(status: "consumed")
            else
              reservation.update!(quantity: reservation.quantity - consume_quantity)
            end
          end

          WriteMovement.call(
            stock_item: stock_item,
            delta: -consume_quantity,
            reason: "fulfilled",
            reference: @fulfillment_line_item
          )

          order_line_item.update!(fulfilled_quantity: order_line_item.fulfilled_quantity.to_i + consume_quantity)
        end
      end

      Reservations::RecountStockItem.call(stock_item) if stock_item
      update_order_fulfillment_status! if @update_order_status
      @fulfillment_line_item.reload
    end

    private

    def order_line_item
      @order_line_item ||= @fulfillment_line_item.order_line_item
    end

    def order
      @order ||= order_line_item.order
    end

    def remaining_quantity
      [ order_line_item.quantity.to_i - order_line_item.fulfilled_quantity.to_i, 0 ].max
    end

    def already_moved?
      StockMovement.exists?(
        reference_type: @fulfillment_line_item.class.name,
        reference_id: @fulfillment_line_item.id.to_s,
        reason: "fulfilled"
      )
    end

    def fallback_stock_item
      variant = order_line_item.variant
      return nil unless variant

      warehouse = @warehouse || WarehouseResolver.for_shopify_location(
        @fulfillment_line_item.fulfillment.location_id,
        fallback: WarehouseResolver.for_order(order),
        auto_create: true
      ) || WarehouseResolver.for_order(order)
      return nil unless warehouse

      StockItem.find_or_create_by!(variant: variant, warehouse: warehouse) do |stock_item|
        stock_item.quantity_on_hand = 0
      end
    end

    def update_order_fulfillment_status!
      totals = order.line_items.pluck(:quantity, :fulfilled_quantity)
      fulfilled = totals.sum { |_, fulfilled_quantity| fulfilled_quantity.to_i }
      ordered = totals.sum { |quantity, _| quantity.to_i }

      fulfillment_status = if fulfilled <= 0
        nil
      elsif fulfilled >= ordered
        "fulfilled"
      else
        "partial"
      end

      # Always persist fulfillment_status directly (no state-machine counterpart).
      new_status = order.status
      new_status = "fulfilled"   if fulfillment_status == "fulfilled" && %w[pending processing].include?(new_status)
      new_status = "processing"  if fulfillment_status == "partial"   && new_status == "pending"

      # Use the state machine when the status axis actually changes so that
      # side-effects (COGS, audit log) are triggered correctly.
      order.update!(fulfillment_status: fulfillment_status)
      if new_status != order.status
        ::Sales::OrderStateMachine.call(order, to: new_status)
      end
    end
  end
end
