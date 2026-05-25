# Inventory::Shopify::StockSyncService
#
# Syncs a Shopify `inventory_levels/update` webhook payload into StockItem.
# Payload shape from Shopify:
#   { "inventory_item_id" => 12345, "location_id" => 67890, "available" => 10, ... }
#
# We match variant by shopify_inventory_item_id and warehouse by a custom
# shopify_location_id column — or create/find a "Shopify / <location_id>" warehouse.
#
class Inventory::Shopify::StockSyncService
  REASON = "shopify_sync"

  def self.call(payload, reference: nil)
    new(payload, reference: reference).call
  end

  def initialize(payload, reference: nil)
    @payload   = payload
    @reference = reference
  end

  def call
    ::Shopify::Origin.without_read_only do
      inventory_item_id = Integer(@payload["inventory_item_id"])
      location_id       = Integer(@payload["location_id"])
      available         = Integer(@payload["available"].to_i)
      committed         = committed_quantity

      variant = Variant.find_by(shopify_inventory_item_id: inventory_item_id)
      return nil unless variant

      warehouse = ::Inventory::WarehouseResolver.for_shopify_location(location_id, auto_create: true)

      ActiveRecord::Base.transaction do
        stock_item = StockItem.find_or_initialize_by(
          variant_id:   variant.id,
          warehouse_id: warehouse.id
        )
        stock_item.quantity_on_hand ||= 0
        stock_item.save!

        ::Inventory::WriteShopifyMirrorMovement.call(
          stock_item: stock_item,
          reason: REASON,
          reference: @reference,
          on_hand_absolute: available,
          committed_absolute: committed
        )

        stock_item.update!(shopify_last_synced_at: Time.current)

        ::Inventory::Reservations::RecountStockItem.call(stock_item.reload)

        stock_item
      end
    end
  end

  private

  def committed_quantity
    value = @payload["committed"] || @payload[:committed] ||
            @payload["committed_quantity"] || @payload[:committed_quantity]
    value.nil? ? nil : Integer(value.to_i)
  end
end
