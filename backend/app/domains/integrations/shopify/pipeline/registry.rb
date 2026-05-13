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
        shopify_inventory_level_connected: :inventory,
        shopify_inventory_level_disconnected: :inventory,
        shopify_inventory_item_created: :noop,
        shopify_inventory_item_updated: :noop,
        shopify_inventory_item_deleted: :noop,
        shopify_order_created: :order,
        shopify_order_updated: :order,
        shopify_order_paid: :order,
        shopify_order_cancelled: :order,
        shopify_order_edited: :order,
        shopify_order_fulfilled: :order,
        shopify_order_partially_fulfilled: :order,
        shopify_refund_created: :refund,
        shopify_fulfillment_created: :fulfillment,
        shopify_fulfillment_updated: :fulfillment,
        shopify_fulfillment_cancelled: :fulfillment,
        shopify_customer_created: :customer,
        shopify_customer_updated: :customer,
        shopify_customer_data_requested: :noop,
        shopify_customer_redacted: :noop,
        shopify_shop_redacted: :noop,
        shopify_app_uninstalled: :noop
      }.freeze

      def self.handler_for(event_type)
        HANDLERS.fetch(event_type.to_sym)
      end
    end
  end
end