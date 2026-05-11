module Inventory
  class ReservationsCommand
    def self.reserve(order_line_item:, stock_item:, quantity:, note: nil)
      new(order_line_item).reserve(stock_item: stock_item, quantity: quantity, note: note)
    end

    def self.release(order_line_item:, quantity: nil)
      new(order_line_item).release(quantity: quantity)
    end

    def self.consume(order_line_item:, quantity:, stock_item: nil)
      new(order_line_item).consume(quantity: quantity, stock_item: stock_item)
    end

    def initialize(order_line_item)
      @order_line_item = order_line_item
      @affected_stock_item_ids = []
    end

    def reserve(stock_item:, quantity:, note: nil)
      quantity = quantity.to_i
      return release if quantity <= 0

      ActiveRecord::Base.transaction do
        lock_order_line!
        stock_item = StockItem.lock.find(stock_item.id)
        release_other_active_reservations!(stock_item)

        reservation = @order_line_item.stock_reservations.active.where(stock_item: stock_item).first
        was_new = reservation.nil?
        previous_quantity = reservation&.quantity.to_i
        reservation ||= @order_line_item.stock_reservations.build(stock_item: stock_item, status: "active")
        reservation.quantity = quantity
        reservation.note = note
        reservation.save!

        if was_new || previous_quantity != quantity
          record_reservation_delta(stock_item, previous_quantity, quantity, note)
        end
        @affected_stock_item_ids << stock_item.id
      end

      recount_affected!
      @order_line_item.reload.stock_reservations.active.first
    end

    def release(quantity: nil)
      remaining = quantity&.to_i
      released = 0

      ActiveRecord::Base.transaction do
        lock_order_line!
        active_reservations.each do |reservation|
          break if remaining && remaining <= 0

          stock_item = StockItem.lock.find(reservation.stock_item_id)
          take = remaining ? [reservation.quantity.to_i, remaining].min : reservation.quantity.to_i
          next if take <= 0

          if take >= reservation.quantity.to_i
            reservation.update!(status: "released")
          else
            reservation.update!(quantity: reservation.quantity.to_i - take)
          end
          remaining -= take if remaining
          released += take
          @affected_stock_item_ids << stock_item.id
          write_event(stock_item, "reservation_released", take, "released #{take}")
        end
      end

      recount_affected!
      released
    end

    def consume(quantity:, stock_item: nil)
      remaining = quantity.to_i
      consumed = 0
      return consumed if remaining <= 0

      ActiveRecord::Base.transaction do
        lock_order_line!
        scope = active_reservations
        scope = scope.where(stock_item_id: stock_item.id) if stock_item
        scope.each do |reservation|
          break if remaining <= 0

          locked_stock_item = StockItem.lock.find(reservation.stock_item_id)
          take = [reservation.quantity.to_i, remaining].min
          next if take <= 0

          if take >= reservation.quantity.to_i
            reservation.update!(status: "consumed")
          else
            reservation.update!(quantity: reservation.quantity.to_i - take)
          end
          remaining -= take
          consumed += take
          @affected_stock_item_ids << locked_stock_item.id
          write_event(locked_stock_item, "reservation_consumed", take, "consumed #{take}")
        end
      end

      recount_affected!
      consumed
    end

    private

    def lock_order_line!
      @order_line_item.lock!
      advisory_lock!(@order_line_item.id)
    end

    def advisory_lock!(key)
      quoted = ActiveRecord::Base.connection.quote("stock-reservation:#{key}")
      ActiveRecord::Base.connection.execute("SELECT pg_advisory_xact_lock(hashtext(#{quoted}))")
    rescue ActiveRecord::StatementInvalid
      true
    end

    def active_reservations
      @order_line_item.stock_reservations.active.lock.order(:created_at, :id)
    end

    def release_other_active_reservations!(stock_item)
      @order_line_item.stock_reservations.active.where.not(stock_item_id: stock_item.id).lock.each do |reservation|
        previous_stock_item = StockItem.lock.find(reservation.stock_item_id)
        quantity = reservation.quantity.to_i
        reservation.update!(status: "released")
        @affected_stock_item_ids << previous_stock_item.id
        write_event(previous_stock_item, "reservation_released", quantity, "released #{quantity} due to warehouse switch")
      end
    end

    def write_event(stock_item, reason, quantity, note)
      Inventory::WriteMovement.call(
        stock_item: stock_item,
        delta: 0,
        reason: reason,
        reference: @order_line_item,
        note: note
      )
    end

    def record_reservation_delta(stock_item, previous_quantity, quantity, note)
      delta = quantity - previous_quantity
      return if delta.zero?

      if delta.positive?
        write_event(stock_item, "reserved", delta, "reserved #{delta}#{note.present? ? " (#{note})" : ""}")
      else
        write_event(stock_item, "reservation_released", delta.abs, "released #{delta.abs} due to reservation reduction")
      end
    end

    def recount_affected!
      @affected_stock_item_ids.uniq.each do |stock_item_id|
        stock_item = StockItem.find_by(id: stock_item_id)
        Reservations::RecountStockItem.call(stock_item) if stock_item
      end
    end
  end
end