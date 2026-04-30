module Catalog
  # Job that handles a Shopify product webhook event: resolves the Shopify
  # product payload and upserts it into the ERP catalog.
  class HandleShopifyProductJob < ApplicationJob
    queue_as :default

    def perform(payload)
      Catalog::Shopify::ProductUpserter.call(payload, from: :webhook)
    end
  end
end
