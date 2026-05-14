module Inventory
  class SyncOrderReservations
    def self.call(order, warehouse: nil, warehouse_id: nil)
      new(order, warehouse: warehouse, warehouse_id: warehouse_id).call
    end

    def initialize(order, warehouse: nil, warehouse_id: nil)
      @order = order
      @warehouse = warehouse
      @warehouse_id = warehouse_id
      @affected_stock_item_ids = []
      @shortages = []
    end

    def call
      ActiveRecord::Base.transaction do
        warehouse = WarehouseResolver.for_order(@order, warehouse: @warehouse, warehouse_id: @warehouse_id)
        sync_lines!(warehouse)
        raise Oversold, @shortages if @shortages.any?
      end

      recount_affected!
      @order.reload
    end

    private

    def sync_lines!(warehouse)
      @order.line_items.includes(:variant).each do |line_item|
        if line_item.variant_id.blank?
          release_line!(line_item)
          next
        end

        target_quantity = [line_item.quantity.to_i - line_item.fulfilled_quantity.to_i - cancelled_quantity(line_item), 0].max
        if target_quantity.zero?
          release_line!(line_item)
          next
        end

        stock_item = stock_item_for(line_item, warehouse)
        unless stock_item
          add_shortage(line_item, requested: target_quantity, available: 0)
          next
        end

        stock_item.with_lock do
          current_active = line_item.stock_reservations.active.first
          available_for_line = stock_item.raw_available +
                               (current_active&.stock_item_id == stock_item.id ? current_active.quantity.to_i : 0)

          if manual_stock_guard?(line_item.variant) && available_for_line < target_quantity
            add_shortage(line_item, requested: target_quantity, available: [available_for_line, 0].max)
            next
          end

          if current_active && current_active.stock_item_id != stock_item.id
            @affected_stock_item_ids << current_active.stock_item_id
            ReservationsCommand.release(order_line_item: line_item, quantity: current_active.quantity)
            current_active = nil
          end

          reservation_quantity = reservation_quantity_for(target_quantity, available_for_line)
          if reservation_quantity <= 0
            ReservationsCommand.release(order_line_item: line_item) if current_active
            @affected_stock_item_ids << stock_item.id
            next
          end

          ReservationsCommand.reserve(
            order_line_item: line_item,
            stock_item: stock_item,
            quantity: reservation_quantity,
            note: partial_note(reservation_quantity, target_quantity)
          )
          @affected_stock_item_ids << stock_item.id
        end
      end
    end

    def release_line!(line_item)
      line_item.stock_reservations.active.find_each do |reservation|
        @affected_stock_item_ids << reservation.stock_item_id
      end
      ReservationsCommand.release(order_line_item: line_item)
      true
    end

    def stock_item_for(line_item, warehouse)
      variant = line_item.variant
      return nil unless variant
      return nil if manual_stock_guard?(variant) && shopify_locked_variant?(variant)
      return nil if manual_stock_guard?(variant) && warehouse&.shopify_origin?

      stock_item = StockItem.find_by(variant: variant, warehouse: warehouse) if warehouse
      return nil if manual_stock_guard?(variant) && stock_item&.shopify_origin?
      return stock_item if stock_item

      if warehouse && !manual_stock_guard?(variant)
        return StockItem.create!(variant: variant, warehouse: warehouse, quantity_on_hand: 0)
      end

      scope = StockItem.where(variant: variant)
               .joins(:warehouse)
               .where(warehouses: { active: true })
      scope = scope.where(warehouses: { shopify_location_id: nil }) if manual_stock_guard?(variant)
      scope.order(Arel.sql("(stock_items.quantity_on_hand - stock_items.quantity_reserved - stock_items.quantity_unavailable) DESC"))
           .first
    end

    def manual_stock_guard?(variant)
      @order.source != "shopify" && variant&.inventory_policy.to_s != "continue"
    end

    def shopify_locked_variant?(variant)
      variant&.shopify_origin? || variant&.product&.shopify_origin?
    end

    def cancelled_quantity(line_item)
      line_item.refund_line_items.where(restock_type: "cancel").sum(:quantity).to_i
    end

    def reservation_quantity_for(target_quantity, available_for_line)
      return [[available_for_line, 0].max, target_quantity].min if @order.source == "shopify"

      target_quantity
    end

    def partial_note(reservation_quantity, target_quantity)
      return nil unless @order.source == "shopify"
      return nil if reservation_quantity >= target_quantity

      "partial"
    end

    def add_shortage(line_item, requested:, available:)
      @shortages << {
        order_line_item_id: line_item.id,
        variant_id: line_item.variant_id,
        sku: line_item.sku || line_item.variant&.sku,
        title: line_item.title,
        requested: requested,
        available: available
      }
    end

    def recount_affected!
      @affected_stock_item_ids.uniq.each do |stock_item_id|
        stock_item = StockItem.find_by(id: stock_item_id)
        Reservations::RecountStockItem.call(stock_item) if stock_item
      end
    end
  end
end