class CustomerSerializer
  def self.call(customer, include_orders: false, include_last_order: false)
    last_order = include_last_order ? customer.last_order : nil

    {
      id:                   customer.id,
      email:                customer.email,
      phone:                customer.phone,
      first_name:           customer.first_name,
      last_name:            customer.last_name,
      display_name:         customer.display_name,
      tags:                 customer.tags,
      default_address:      customer.default_address,
      addresses:            customer.addresses,
      accepts_marketing:    customer.accepts_marketing,
      verified_email:       customer.verified_email,
      tax_exempt:           customer.tax_exempt,
      state:                customer.state,
      note:                 customer.note,
      last_order_id:        customer.last_order_id,
      last_order_name:      customer.last_order_name,
      last_order_at:        customer.last_order_at,
      last_order:           last_order ? OrderSerializer.call(last_order, include_line_items: true) : nil,
      orders_count:         customer.orders_count,
      total_spent:          customer.total_spent,
      currency:             customer.currency,
      source:               customer.source,
      shopify_customer_id:  customer.shopify_customer_id,
      created_at:           customer.created_at,
      updated_at:           customer.updated_at,
      orders: include_orders ? customer.orders.recent.limit(50).map { |o| OrderSerializer.call(o, include_line_items: false) } : nil
    }.compact
  end
end
