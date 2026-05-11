class FulfillmentSerializer
  def self.call(fulfillment, include_line_items: true)
    order = fulfillment.order
    {
      id:                      fulfillment.id,
      order_id:                fulfillment.order_id,
      order:                   order ? order_summary(order) : nil,
      customer:                order ? customer_summary(order) : nil,
      status:                  fulfillment.status,
      tracking_company:        fulfillment.tracking_company,
      tracking_number:         fulfillment.tracking_number,
      tracking_url:            fulfillment.tracking_url,
      carrier:                 fulfillment.bosta? ? "bosta" : fulfillment.tracking_company,
      delivery_status:         fulfillment.delivery_status,
      service:                 fulfillment.service,
      notes:                   fulfillment.respond_to?(:notes) ? fulfillment.notes : nil,
      tags:                    fulfillment.respond_to?(:tags) ? fulfillment.tags : [],
      carrier_data:            fulfillment.respond_to?(:carrier_data) ? fulfillment.carrier_data : {},
      shipped_at:              fulfillment.shipped_at,
      delivered_at:            fulfillment.delivered_at,
      in_transit_at:           (fulfillment.respond_to?(:in_transit_at) ? fulfillment.in_transit_at : nil),
      location_id:             fulfillment.location_id,
      shopify_fulfillment_id:  fulfillment.shopify_fulfillment_id,
      created_at:              fulfillment.created_at,
      updated_at:              fulfillment.updated_at,
      line_items: include_line_items ? fulfillment.fulfillment_line_items.map { |li| FulfillmentLineItemSerializer.call(li) } : nil
    }.compact
  end

  def self.order_summary(order)
    {
      id: order.id,
      order_number: order.order_number,
      status: order.status,
      financial_status: order.financial_status,
      fulfillment_status: order.fulfillment_status,
      total_price: order.total_price,
      currency: order.currency,
      shipping_address: order.shipping_address
    }
  end

  def self.customer_summary(order)
    {
      id: order.customer_id,
      name: order.customer_name,
      email: order.customer_email,
      phone: order.customer&.phone
    }
  end
end

class FulfillmentLineItemSerializer
  def self.call(item)
    order_line_item = item.order_line_item
    {
      id:                        item.id,
      fulfillment_id:            item.fulfillment_id,
      order_line_item_id:        item.order_line_item_id,
      title:                     order_line_item&.title,
      sku:                       order_line_item&.sku,
      variant_title:             order_line_item&.variant_title,
      quantity:                  item.quantity,
      shopify_line_item_id:      item.shopify_line_item_id
    }
  end
end
