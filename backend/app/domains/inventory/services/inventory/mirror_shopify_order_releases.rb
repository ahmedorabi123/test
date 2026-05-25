module Inventory
  class MirrorShopifyOrderReleases
    def self.call(order)
      new(order).call
    end

    def initialize(order)
      @order = order
    end

    def call
      return unless @order.source == "shopify"

      @order.line_items.includes(stock_reservations: :stock_item).find_each do |line_item|
        line_item.stock_reservations.active.each do |reservation|
          stock_item = reservation.stock_item
          next unless mirrorable?(stock_item)
          release_delta = reservation.quantity.to_i - mirrored_released_quantity(line_item)
          next if release_delta <= 0

          Inventory::WriteShopifyMirrorMovement.call(
            stock_item: stock_item,
            reason: "shopify_mirror_order_released",
            reference: line_item,
            committed_delta: -release_delta,
            note: "Shopify order released #{release_delta} committed units"
          )
        end
      end
    end

    private

    def mirrorable?(stock_item)
      stock_item&.warehouse&.shopify_origin? && stock_item.variant&.shopify_inventory_item_id.present?
    end

    def mirrored_released_quantity(line_item)
      StockMovement.where(
        movement_scope: "shopify_mirror",
        reason: "shopify_mirror_order_released",
        reference_type: line_item.class.name,
        reference_id: line_item.id.to_s
      ).sum(:committed_delta).to_i.abs
    end
  end
end
