module Shopify
  # Normalizes raw Shopify webhook payloads into typed domain events.
  # Domain modules subscribe to these events rather than coupling to
  # Shopify's data shape directly.
  #
  # Returns a Hash: { type: Symbol, data: Hash, occurred_at: Time }
  class EventNormalizer
    SUPPORTED_TOPICS = {
      "orders/create"             => :shopify_order_created,
      "orders/updated"            => :shopify_order_updated,
      "orders/paid"               => :shopify_order_paid,
      "orders/cancelled"          => :shopify_order_cancelled,
      "orders/edited"             => :shopify_order_edited,
      "orders/fulfilled"          => :shopify_order_fulfilled,
      "orders/partially_fulfilled" => :shopify_order_partially_fulfilled,
      "refunds/create"            => :shopify_refund_created,
      "products/create"           => :shopify_product_created,
      "products/update"           => :shopify_product_updated,
      "products/delete"           => :shopify_product_deleted,
      "collections/create"        => :shopify_collection_created,
      "collections/update"        => :shopify_collection_updated,
      "collections/delete"        => :shopify_collection_deleted,
      "inventory_items/create"    => :shopify_inventory_item_created,
      "inventory_items/update"    => :shopify_inventory_item_updated,
      "inventory_items/delete"    => :shopify_inventory_item_deleted,
      "inventory_levels/connect"  => :shopify_inventory_level_connected,
      "inventory_levels/disconnect" => :shopify_inventory_level_disconnected,
      "inventory_levels/update"   => :shopify_inventory_updated,
      "customers/create"          => :shopify_customer_created,
      "customers/update"          => :shopify_customer_updated,
      "customers/data_request"    => :shopify_customer_data_requested,
      "customers/redact"          => :shopify_customer_redacted,
      "fulfillments/create"       => :shopify_fulfillment_created,
      "fulfillments/update"       => :shopify_fulfillment_updated,
      "fulfillments/cancelled"    => :shopify_fulfillment_cancelled,
      "shop/redact"               => :shopify_shop_redacted,
      "app/uninstalled"           => :shopify_app_uninstalled
    }.freeze

    class UnsupportedTopicError < StandardError; end

    def self.normalize(topic:, payload:)
      event_type = SUPPORTED_TOPICS[topic]
      raise UnsupportedTopicError, "Unsupported Shopify topic: #{topic}" unless event_type

      {
        type:        event_type,
        source:      "shopify",
        topic:       topic,
        external_id: extract_external_id(topic, payload),
        data:        payload,
        occurred_at: extract_occurred_at(payload)
      }
    end

    def self.supports?(topic)
      SUPPORTED_TOPICS.key?(topic)
    end

    def self.extract_external_id(topic, payload)
      # Shopify payload always has "id" at the top level for most resources;
      # inventory_levels uses "inventory_item_id".
      payload["id"].presence ||
        payload["admin_graphql_api_id"].presence ||
        payload["inventory_item_id"].presence ||
        payload["shop_id"].presence ||
        payload["shop_domain"].presence ||
        payload.dig("customer", "id").presence ||
        "#{topic}-#{SecureRandom.hex(8)}"
    end

    def self.extract_occurred_at(payload)
      ts = payload["updated_at"] || payload["created_at"] || payload["processed_at"]
      ts.present? ? Time.zone.parse(ts.to_s) : Time.current
    rescue ArgumentError
      Time.current
    end
  end
end
