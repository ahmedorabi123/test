module Sales
  class HandleShopifyRefundJob < ApplicationJob
    queue_as :default

    def perform(payload)
      Sales::Shopify::RefundUpserter.call(payload)
    end
  end
end
