module Shopify
  # Normalizes raw Shopify webhook payloads into typed domain events.
  # Domain modules subscribe to these events rather than coupling to
  # Shopify's data shape directly.
  #
  # Returns a Hash: { type: Symbol, data: Hash, occurred_at: Time }
  class EventNormalizer
    SUPPORTED_TOPICS = {
      "orders/create"         => :shopify_order_created,
      "orders/updated"        => :shopify_order_updated,
      "orders/paid"           => :shopify_order_paid,
      "orders/cancelled"      => :shopify_order_cancelled,
      "orders/fulfilled"      => :shopify_order_fulfilled,
      "refunds/create"        => :shopify_refund_created,
      "products/create"       => :shopify_product_created,
      "products/update"       => :shopify_product_updated,
      "inventory_levels/update" => :shopify_inventory_updated,
      "customers/create"      => :shopify_customer_created,
      "customers/update"      => :shopify_customer_updated,
      "fulfillments/create"   => :shopify_fulfillment_created,
      "fulfillments/update"   => :shopify_fulfillment_updated
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
