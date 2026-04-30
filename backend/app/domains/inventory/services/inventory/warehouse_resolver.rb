module Inventory
  # Resolves which warehouse a fulfillment/refund operation should touch.
  # Priority:
  #   1. Warehouse with matching shopify_location_id
  #   2. Auto-create a SHOPIFY-<id> warehouse (matches StockSyncService convention)
  #   3. Caller-provided fallback (e.g. primary warehouse)
  class WarehouseResolver
    def self.for_shopify_location(location_id, fallback: nil, auto_create: true)
      return fallback if location_id.blank?

      id = location_id.to_i
      return fallback if id.zero?

      wh = Warehouse.find_by(shopify_location_id: id)
      return wh if wh

      if auto_create
        Warehouse.find_or_create_by!(code: "SHOPIFY-#{id}") do |w|
          w.name                = "Shopify Location #{id}"
          w.shopify_location_id = id
        end
      else
        fallback
      end
    end

    def self.primary
      Warehouse.where(active: true).order(:created_at).first
    end
  end
end
