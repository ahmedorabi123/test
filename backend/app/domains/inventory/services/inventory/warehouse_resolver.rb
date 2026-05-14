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

    def self.for_order(order, warehouse: nil, warehouse_id: nil)
      return warehouse if warehouse.present?
      return Warehouse.find_by(id: warehouse_id) if warehouse_id.present?

      if order.location_id.present?
        resolved = for_shopify_location(order.location_id, auto_create: false)
        return resolved if resolved
      end

      variant_ids = order.line_items.map(&:variant_id).compact
      if variant_ids.any?
        stock_scope = StockItem
          .joins(:warehouse)
          .where(variant_id: variant_ids, warehouses: { active: true })

        stock_scope = stock_scope.where(warehouses: { shopify_location_id: nil }) if order.source != "shopify"

        best_id = stock_scope
          .group(:warehouse_id)
          .order(Arel.sql("SUM(stock_items.quantity_on_hand - stock_items.quantity_reserved - stock_items.quantity_unavailable) DESC"))
          .limit(1)
          .pluck(:warehouse_id)
          .first
        return Warehouse.find_by(id: best_id) if best_id
      end

      primary
    end
  end
end
