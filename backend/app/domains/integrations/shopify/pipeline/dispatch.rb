module Shopify
  module Pipeline
    class Dispatch
      def self.call(normalized)
        new(normalized).call
      end

      def initialize(normalized)
        @normalized = normalized
        @event_type = normalized.fetch(:type).to_sym
        @payload = normalized.fetch(:data)
      end

      def call
        case Registry.handler_for(@event_type)
        when :product
          Catalog::HandleShopifyProductJob.perform_later(@payload)
        when :product_deleted
          archive_product!
        when :collection
          Catalog::HandleShopifyCollectionJob.perform_later(@payload, kind: collection_kind)
        when :collection_deleted
          ::Shopify::Origin.without_read_only do
            Collection.where(shopify_collection_id: @payload["id"].to_i).destroy_all
          end
        when :inventory
          Inventory::HandleShopifyInventoryJob.perform_later(@payload)
        when :order
          Sales::HandleShopifyOrderJob.perform_later(@payload)
        when :fulfillment
          Shipping::HandleShopifyFulfillmentJob.perform_later(@payload)
        when :refund
          Sales::HandleShopifyRefundJob.perform_later(@payload)
        when :customer
          Crm::HandleShopifyCustomerJob.perform_later(@payload)
        when :noop
          ::Shopify::ComplianceEventJob.perform_later(@normalized[:topic], @payload)
        end
      end

      private

      def archive_product!
        ::Shopify::Origin.without_read_only do
          Product.find_by(shopify_product_id: @payload["id"].to_i)&.update(status: "archived")
        end
      end

      def collection_kind
        @payload["rules"].present? ? "smart" : "custom"
      end
    end
  end
end