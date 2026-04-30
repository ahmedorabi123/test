module Catalog
  module Shopify
    # Paginates all products from the Shopify Admin REST API and upserts them.
    # Safe to re-run. Intended to be executed via the `catalog:shopify:backfill_products`
    # rake task or from a Rails console.
    class ProductBackfillService
      PAGE_SIZE = 50

      def self.call(client: ::Shopify::Client.new, logger: Rails.logger)
        new(client: client, logger: logger).call
      end

      def initialize(client:, logger:)
        @client = client
        @logger = logger
      end

      def call
        imported = 0
        page_info = nil

        loop do
          path = "products.json?limit=#{PAGE_SIZE}"
          path += "&page_info=#{page_info}" if page_info
          response = @client.get(path)
          products = Array(response["products"])
          break if products.empty?

          products.each do |p|
            ProductUpserter.call(p, from: :graphql)
            imported += 1
          end

          @logger.info("[Catalog::Shopify::ProductBackfill] imported=#{imported}")
          page_info = response["_page_info"] # REST pagination via Link headers not exposed by client; stop after one page
          break if page_info.nil?
        end

        imported
      end
    end
  end
end
