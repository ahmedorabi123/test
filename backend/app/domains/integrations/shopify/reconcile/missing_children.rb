module Shopify
  module Reconcile
    class MissingChildren
      def self.call(client:, force: false, log: ->(_message) {}, warn_prefix: "[catchup]")
        new(client: client, force: force, log: log, warn_prefix: warn_prefix).call
      end

      def initialize(client:, force:, log:, warn_prefix:)
        @client = client
        @force = force
        @log = log
        @warn_prefix = warn_prefix
        @totals = { fulfillments: 0, refunds: 0 }
      end

      def call
        catch_up_fulfillments
        catch_up_refunds
        totals
      end

      private

      attr_reader :client, :force, :log, :warn_prefix, :totals

      def catch_up_fulfillments
        order_ids = missing_fulfillment_order_ids

        if order_ids.any?
          log.call "Fulfillments catch-up: #{order_ids.size} orders missing fulfillments - fetching ..."
          fetch_orders(order_ids, label: "fulfillments") do |order_payload|
            Array(order_payload["fulfillments"]).each do |fulfillment_payload|
              Shipping::Shopify::FulfillmentUpserter.call(fulfillment_payload.merge("order_id" => order_payload["id"]))
              totals[:fulfillments] += 1
            rescue => e
              warn "#{warn_prefix} fulfillment #{fulfillment_payload["id"]} (catch-up) failed: #{e.class}: #{e.message}"
            end
          end
          log.call "  fulfillments caught up: #{totals[:fulfillments]}"
        else
          log.call "Fulfillments: all up to date - skipping catch-up"
        end
      end

      def catch_up_refunds
        order_ids = missing_refund_order_ids

        if order_ids.any?
          log.call "Refunds catch-up: #{order_ids.size} orders missing refunds - fetching ..."
          fetch_orders(order_ids, label: "refunds") do |order_payload|
            Array(order_payload["refunds"]).each do |refund_payload|
              Sales::Shopify::RefundUpserter.call(refund_payload)
              totals[:refunds] += 1
            rescue => e
              warn "#{warn_prefix} refund #{refund_payload["id"]} (catch-up) failed: #{e.class}: #{e.message}"
            end
          end
          log.call "  refunds caught up: #{totals[:refunds]}"
        else
          log.call "Refunds: all up to date - skipping catch-up"
        end
      end

      def fetch_orders(order_ids, label:)
        order_ids.each_slice(250) do |ids_batch|
          body = client.get("orders.json", params: { ids: ids_batch.join(","), limit: 250, status: "any" })
          Array(body["orders"]).each { |order_payload| yield order_payload }
        rescue => e
          warn "#{warn_prefix} #{label} batch #{ids_batch.first}.. failed: #{e.class}: #{e.message}"
        end
      end

      def missing_fulfillment_order_ids
        if force
          Order.where.not(shopify_order_id: nil).pluck(:shopify_order_id)
        else
          Order.where.not(shopify_order_id: nil)
               .where.not(fulfillment_status: [nil, "unfulfilled"])
               .where.not(id: Fulfillment.select(:order_id))
               .pluck(:shopify_order_id)
        end
      end

      def missing_refund_order_ids
        if force
          Order.where.not(shopify_order_id: nil).pluck(:shopify_order_id)
        else
          Order.where.not(shopify_order_id: nil)
               .where(financial_status: %w[refunded partially_refunded])
               .where.not(id: Refund.select(:order_id))
               .pluck(:shopify_order_id)
        end
      end
    end
  end
end
