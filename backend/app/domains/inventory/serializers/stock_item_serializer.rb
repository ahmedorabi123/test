class StockItemSerializer
  def self.call(stock_item)
    variant   = stock_item.variant
    warehouse = stock_item.warehouse
    {
      id:                    stock_item.id,
      variant_id:            stock_item.variant_id,
      warehouse_id:          stock_item.warehouse_id,
      sku:                   variant&.sku,
      variant_title:         variant&.title,
      product_title:         variant&.product&.title,
      warehouse_name:        warehouse&.name,
      quantity_on_hand:      stock_item.quantity_on_hand,
      quantity_reserved:     stock_item.quantity_reserved,
      quantity_unavailable:  stock_item.quantity_unavailable,
      shopify_quantity_on_hand: stock_item.shopify_quantity_on_hand,
      shopify_quantity_committed: stock_item.shopify_quantity_committed,
      shopify_available:     stock_item.shopify_available,
      shopify_last_synced_at: stock_item.shopify_last_synced_at,
      shopify_divergence:    stock_item.shopify_divergence,
      unavailability_reason: stock_item.unavailability_reason,
      available:             stock_item.available,
      low_stock_threshold:   stock_item.low_stock_threshold,
      low_stock:             stock_item.low_stock?,
      read_only_origin:      stock_item.shopify_origin?,
      updated_at:            stock_item.updated_at
    }
  end
end
