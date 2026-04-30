module Shipping
  module Adapters
    # Placeholder adapter for the Bosta shipping API. Currently Bosta is wired
    # through Shopify (tracking_company == "Bosta" on fulfillments) — when
    # direct integration is enabled, these methods should be implemented.
    class BostaAdapter
      class NotImplementedYet < StandardError; end

      # Create a shipment on Bosta for the given fulfillment/order.
      def self.create_shipment(_fulfillment)
        raise NotImplementedYet, "Direct Bosta API not enabled; using Shopify-mediated flow"
      end

      # Track a shipment by Bosta tracking number.
      def self.track(tracking_number)
        { tracking_number: tracking_number, status: "unknown", source: "stub" }
      end

      # Cancel a shipment.
      def self.cancel(_tracking_number)
        raise NotImplementedYet, "Direct Bosta API not enabled"
      end

      def self.enabled?
        ENV["BOSTA_DIRECT_ENABLED"] == "true"
      end
    end
  end
end
