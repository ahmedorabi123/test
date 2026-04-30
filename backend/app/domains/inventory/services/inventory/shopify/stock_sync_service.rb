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
    inventory_item_id = Integer(@payload["inventory_item_id"])
    location_id       = Integer(@payload["location_id"])
    available         = Integer(@payload["available"].to_i)

    variant   = Variant.find_by(shopify_inventory_item_id: inventory_item_id)
    return nil unless variant

    warehouse = find_or_create_warehouse(location_id)

    ActiveRecord::Base.transaction do
      stock_item = StockItem.find_or_initialize_by(
        variant_id:   variant.id,
        warehouse_id: warehouse.id
      )
      before = stock_item.persisted? ? stock_item.quantity_on_hand : 0
      delta  = available - before

      stock_item.quantity_on_hand = available
      stock_item.save!

      if delta != 0
        StockMovement.create!(
          stock_item:      stock_item,
          delta:           delta,
          reason:          REASON,
          reference_type:  @reference&.class&.name,
          reference_id:    @reference&.id&.to_s,
          snapshot_before: before,
          snapshot_after:  available
        )
      end

      stock_item
    end
  end

  private

  def find_or_create_warehouse(location_id)
    code = "SHOPIFY-#{location_id}"
    Warehouse.find_or_create_by!(code: code) do |w|
      w.name = "Shopify Location #{location_id}"
    end
  end
end
