module Crm
  class HandleShopifyCustomerJob < ApplicationJob
    queue_as :default

    def perform(payload)
      Crm::Shopify::CustomerUpserter.call(payload)
    end
  end
end
