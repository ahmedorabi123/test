module Inventory
  class WriteShopifyMirrorMovement
    SCOPE = "shopify_mirror".freeze

    def self.call(stock_item:, reason:, reference: nil, on_hand_delta: nil, committed_delta: nil,
                  on_hand_absolute: nil, committed_absolute: nil, note: nil, idempotent: false)
      new(
        stock_item: stock_item,
        reason: reason,
        reference: reference,
        on_hand_delta: on_hand_delta,
        committed_delta: committed_delta,
        on_hand_absolute: on_hand_absolute,
        committed_absolute: committed_absolute,
        note: note,
        idempotent: idempotent
      ).call
    end

    def initialize(stock_item:, reason:, reference:, on_hand_delta:, committed_delta:,
                   on_hand_absolute:, committed_absolute:, note:, idempotent:)
      @stock_item = stock_item
      @reason = reason.to_s
      @reference = reference
      @on_hand_delta = on_hand_delta
      @committed_delta = committed_delta
      @on_hand_absolute = on_hand_absolute
      @committed_absolute = committed_absolute
      @note = note
      @idempotent = idempotent
    end

    def call
      return existing_movement if idempotent_movement_exists?

      ::Shopify::Origin.without_read_only do
        StockItem.transaction do
          stock_item = StockItem.lock.find(@stock_item.id)
          before_on_hand = stock_item.shopify_quantity_on_hand || stock_item.quantity_on_hand.to_i
          before_committed = stock_item.shopify_quantity_committed || stock_item.quantity_reserved.to_i

          after_on_hand = next_value(before_on_hand, @on_hand_delta, @on_hand_absolute)
          after_committed = next_value(before_committed, @committed_delta, @committed_absolute)

          after_on_hand = 0 if after_on_hand.negative?
          after_committed = 0 if after_committed.negative?

          on_hand_delta = after_on_hand - before_on_hand
          committed_delta = after_committed - before_committed
          return nil if on_hand_delta.zero? && committed_delta.zero? && @note.blank?

          stock_item.update!(
            shopify_quantity_on_hand: after_on_hand,
            shopify_quantity_committed: after_committed
          )

          StockMovement.create!(
            stock_item: stock_item,
            delta: on_hand_delta.zero? ? committed_delta : on_hand_delta,
            reason: @reason,
            reference_type: @reference&.class&.name,
            reference_id: @reference&.id&.to_s,
            snapshot_before: before_on_hand,
            snapshot_after: after_on_hand,
            note: @note,
            movement_scope: SCOPE,
            committed_delta: committed_delta,
            committed_snapshot_before: before_committed,
            committed_snapshot_after: after_committed
          )
        end
      end
    end

    private

    def next_value(before, delta, absolute)
      return Integer(absolute) unless absolute.nil?
      before + (delta.nil? ? 0 : Integer(delta))
    end

    def idempotent_movement_exists?
      return false unless @idempotent && @reference

      existing_movement.present?
    end

    def existing_movement
      return nil unless @reference

      @existing_movement ||= StockMovement.find_by(
        movement_scope: SCOPE,
        reason: @reason,
        reference_type: @reference.class.name,
        reference_id: @reference.id.to_s
      )
    end
  end
end
