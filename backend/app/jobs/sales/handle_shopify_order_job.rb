module Sales
  # Job that handles a Shopify order webhook event: upserts the order payload
  # into our sales domain.
  class HandleShopifyOrderJob < ApplicationJob
    queue_as :default

    def perform(payload)
      Sales::Shopify::OrderUpserter.call(payload, from: :webhook)
    end
  end
end
