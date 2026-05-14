class OrderSerializer
  def self.call(order, include_line_items: true)
    {
      id:                 order.id,
      order_number:       order.order_number,
      external_number:    order.external_number,
      source:             order.source,
      status:             order.status,
      financial_status:   order.financial_status,
      fulfillment_status: order.fulfillment_status,
      currency:           order.currency,
      subtotal_price:     order.subtotal_price,
      total_tax:          order.total_tax,
      total_shipping:     order.total_shipping,
      total_discount:     order.total_discount,
      total_refunded:     0,
      total_price:        order.total_price,
      customer_email:     order.customer_email,
      customer_name:      order.customer_name,
      shipping_address:   order.shipping_address,
      billing_address:    order.billing_address,
      notes:              order.notes,
      placed_at:          order.placed_at,
      cancelled_at:       order.cancelled_at,
      shopify_order_id:   order.shopify_order_id,
      read_only_origin:   order.shopify_origin?,
      customer_id:        order.customer_id,
      location_id:        order.location_id,
      tags:                     order.tags,
      delivery_method:          order.delivery_method,
      items_count:              order.items_count,
      payment_gateway_names:    order.payment_gateway_names,
      risk_level:               order.risk_level,
      cancel_reason:            order.cancel_reason,
      closed_at:                order.closed_at,
      total_outstanding:        order.total_outstanding,
      shopify_order_status_url: order.shopify_order_status_url,
      delivery_status: order.respond_to?(:last_delivery_status) && order.last_delivery_status.present? \
                         ? order.last_delivery_status \
                         : order.fulfillments.order(created_at: :desc).first&.delivery_status,
      created_at:         order.created_at,
      updated_at:         order.updated_at,
      line_items:   include_line_items ? order.line_items.map { |li| OrderLineItemSerializer.call(li) } : nil,
      fulfillments: include_line_items ? order.fulfillments.order(created_at: :asc).map { |f| FulfillmentSerializer.call(f) } : nil
    }.compact
  end

  def self.stock_allocation(order)
    order.line_items.includes(stock_reservations: { stock_item: :warehouse }).map do |line_item|
      OrderLineItemSerializer.call(line_item).merge(
        reserved_quantity: line_item.stock_reservations.active.sum(:quantity),
        allocations: line_item.stock_reservations.map { |reservation|
          stock_item = reservation.stock_item
          {
            id: reservation.id,
            status: reservation.status,
            quantity: reservation.quantity,
            note: reservation.note,
            stock_item_id: stock_item.id,
            warehouse_id: stock_item.warehouse_id,
            warehouse_name: stock_item.warehouse&.name,
            warehouse_code: stock_item.warehouse&.code,
            on_hand: stock_item.quantity_on_hand,
            reserved: stock_item.quantity_reserved,
            unavailable: stock_item.quantity_unavailable,
            available: stock_item.available
          }
        }
      )
    end
  end
end

class OrderLineItemSerializer
  def self.call(item)
    {
      id:             item.id,
      order_id:       item.order_id,
      variant_id:     item.variant_id,
      sku:            item.sku,
      title:          item.title,
      variant_title:  item.variant_title,
      quantity:       item.quantity,
      price:          item.price,
      total_discount: item.total_discount,
      total_tax:      item.total_tax,
      line_total:     item.line_total,
      fulfilled_quantity: item.respond_to?(:fulfilled_quantity) ? item.fulfilled_quantity : 0,
      reserved_quantity: item.stock_reservations.active.sum(:quantity)
    }
  end
end
