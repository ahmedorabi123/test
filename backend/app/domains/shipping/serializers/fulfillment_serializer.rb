class FulfillmentSerializer
  def self.call(fulfillment, include_line_items: true)
    {
      id:                      fulfillment.id,
      order_id:                fulfillment.order_id,
      status:                  fulfillment.status,
      tracking_company:        fulfillment.tracking_company,
      tracking_number:         fulfillment.tracking_number,
      tracking_url:            fulfillment.tracking_url,
      carrier:                 fulfillment.bosta? ? "bosta" : fulfillment.tracking_company,
      delivery_status:         fulfillment.delivery_status,
      service:                 fulfillment.service,
      shipped_at:              fulfillment.shipped_at,
      delivered_at:            fulfillment.delivered_at,
      location_id:             fulfillment.location_id,
      shopify_fulfillment_id:  fulfillment.shopify_fulfillment_id,
      created_at:              fulfillment.created_at,
      updated_at:              fulfillment.updated_at,
      line_items: include_line_items ? fulfillment.fulfillment_line_items.map { |li| FulfillmentLineItemSerializer.call(li) } : nil
    }.compact
  end
end

class FulfillmentLineItemSerializer
  def self.call(item)
    {
      id:                        item.id,
      fulfillment_id:            item.fulfillment_id,
      order_line_item_id:        item.order_line_item_id,
      quantity:                  item.quantity,
      shopify_line_item_id:      item.shopify_line_item_id
    }
  end
end
