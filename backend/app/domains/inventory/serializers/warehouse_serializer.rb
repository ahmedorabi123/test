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
      read_only_origin: warehouse.shopify_origin?,
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

