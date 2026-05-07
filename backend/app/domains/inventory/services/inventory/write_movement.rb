module Inventory
  # Applies a quantity delta to a StockItem and records an immutable
  # StockMovement row. Positive delta = restock / purchase / return.
  # Negative delta = fulfillment / adjustment out.
  #
  # Will never allow quantity_on_hand to go negative; returns nil + logs
  # if that would happen and `strict` is false. Raises if `strict`.
  class WriteMovement
    class InsufficientStockError < StandardError; end

    def self.call(stock_item:, delta:, reason:, reference: nil, strict: false, note: nil)
      new(stock_item: stock_item, delta: delta, reason: reason,
          reference: reference, strict: strict, note: note).call
    end

    def initialize(stock_item:, delta:, reason:, reference:, strict:, note:)
      @stock_item = stock_item
      @delta      = delta.to_i
      @reason     = reason.to_s
      @reference  = reference
      @strict     = strict
      @note       = note
    end

    def call
      StockItem.transaction do
        si = StockItem.lock.find(@stock_item.id)
        before = si.quantity_on_hand
        after  = before + @delta

        if after.negative?
          raise InsufficientStockError,
                "Cannot move #{@delta} on stock_item #{si.id} (on_hand=#{before})" if @strict

          Rails.logger.warn(
            "[Inventory::WriteMovement] Clamped delta=#{@delta} on stock_item=#{si.id} " \
            "on_hand=#{before} → 0 (reason=#{@reason})"
          )
          @delta = -before
          after  = 0
        end

        return nil if @delta.zero? && @note.blank?

        si.update!(quantity_on_hand: after) if @delta != 0

        StockMovement.create!(
          stock_item:      si,
          delta:           @delta,
          reason:          @reason,
          reference_type:  @reference&.class&.name,
          reference_id:    @reference&.id&.to_s,
          snapshot_before: before,
          snapshot_after:  after,
          note:            @note
        )
      end
    end
  end
end
