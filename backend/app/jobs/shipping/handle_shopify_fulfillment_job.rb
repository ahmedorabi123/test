module Shipping
  class HandleShopifyFulfillmentJob < ApplicationJob
    queue_as :default

    def perform(payload)
      Shipping::Shopify::FulfillmentUpserter.call(payload)
    end
  end
end
