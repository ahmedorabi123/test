module Inventory
  class MirrorShopifyFulfillmentConsumption
    def self.call(fulfillment_line_item)
      new(fulfillment_line_item).call
    end

    def initialize(fulfillment_line_item)
      @fulfillment_line_item = fulfillment_line_item
    end

    def call
      order = @fulfillment_line_item.order_line_item&.order
      return unless order&.source == "shopify"

      movement = StockMovement.find_by(
        movement_scope: "system",
        reason: "fulfilled",
        reference_type: @fulfillment_line_item.class.name,
        reference_id: @fulfillment_line_item.id.to_s
      )
      return unless movement

      stock_item = movement.stock_item
      return unless stock_item&.warehouse&.shopify_origin?

      quantity = movement.delta.to_i.abs
      return if quantity <= 0
      return if shopify_sync_already_covers_fulfillment?(stock_item)
      initialize_missing_on_hand_mirror!(stock_item, movement)

      Inventory::WriteShopifyMirrorMovement.call(
        stock_item: stock_item,
        reason: "shopify_mirror_order_consumed",
        reference: @fulfillment_line_item,
        on_hand_delta: -quantity,
        committed_delta: -quantity,
        idempotent: true,
        note: "Shopify fulfillment consumed #{quantity} units"
      )
    end

    private

    def shopify_sync_already_covers_fulfillment?(stock_item)
      timestamp = @fulfillment_line_item.fulfillment&.shopify_updated_at ||
                  @fulfillment_line_item.fulfillment&.shipped_at ||
                  @fulfillment_line_item.fulfillment&.created_at
      return false unless timestamp

      StockMovement.where(
        stock_item: stock_item,
        movement_scope: "shopify_mirror",
        reason: "shopify_sync"
      ).where("created_at >= ?", timestamp).exists?
    end

    def initialize_missing_on_hand_mirror!(stock_item, movement)
      return unless stock_item.shopify_quantity_on_hand.nil?

      ::Shopify::Origin.without_read_only do
        stock_item.update!(shopify_quantity_on_hand: movement.snapshot_before.to_i)
      end
    end
  end
end
