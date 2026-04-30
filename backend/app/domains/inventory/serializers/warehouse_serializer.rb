class WarehouseSerializer
  def self.call(warehouse, include_stock: false)
    h = {
      id:              warehouse.id,
      name:            warehouse.name,
      code:            warehouse.code,
      kind:            warehouse.kind,
      partner_name:    warehouse.partner_name,
      partner_email:   warehouse.partner_email,
      partner_phone:   warehouse.partner_phone,
      commission_rate: warehouse.commission_rate,
      currency:        warehouse.currency,
      notes:           warehouse.notes,
      address:         warehouse.address,
      active:          warehouse.active,
      shopify_location_id: warehouse.shopify_location_id,
      created_at:      warehouse.created_at,
      updated_at:      warehouse.updated_at
    }
    if include_stock
      h[:stock_items] = warehouse.stock_items.includes(:variant).map do |si|
        StockItemSerializer.call(si)
      end
    end
    h
  end
end

class StockItemSerializer
  def self.call(stock_item)
    variant   = stock_item.variant
    warehouse = stock_item.warehouse
    {
      id:                  stock_item.id,
      variant_id:          stock_item.variant_id,
      warehouse_id:        stock_item.warehouse_id,
      sku:                 variant&.sku,
      variant_title:       variant&.title,
      product_title:       variant&.product&.title,
      warehouse_name:      warehouse&.name,
      quantity_on_hand:    stock_item.quantity_on_hand,
      quantity_reserved:   stock_item.quantity_reserved,
      available:           stock_item.available,
      low_stock_threshold: stock_item.low_stock_threshold,
      low_stock:           stock_item.low_stock?,
      updated_at:          stock_item.updated_at
    }
  end
end
