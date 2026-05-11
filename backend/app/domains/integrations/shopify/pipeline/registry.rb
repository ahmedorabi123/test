module Shopify
  module Pipeline
    class Registry
      HANDLERS = {
        shopify_product_created: :product,
        shopify_product_updated: :product,
        shopify_product_deleted: :product_deleted,
        shopify_collection_created: :collection,
        shopify_collection_updated: :collection,
        shopify_collection_deleted: :collection_deleted,
        shopify_inventory_updated: :inventory,
        shopify_order_created: :order,
        shopify_order_updated: :order,
        shopify_order_paid: :order,
        shopify_order_cancelled: :order,
        shopify_order_fulfilled: :order,
        shopify_refund_created: :refund,
        shopify_fulfillment_created: :fulfillment,
        shopify_fulfillment_updated: :fulfillment,
        shopify_customer_created: :customer,
        shopify_customer_updated: :customer
      }.freeze

      def self.handler_for(event_type)
        HANDLERS.fetch(event_type.to_sym)
      end
    end
  end
end