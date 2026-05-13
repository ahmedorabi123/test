module Shopify
  class ComplianceEventJob < ApplicationJob
    queue_as :webhooks

    def perform(topic, payload)
      Rails.logger.info(
        "[shopify] compliance/no-op topic=#{topic} external_id=#{payload['id'] || payload['shop_id'] || payload['shop_domain']}"
      )
    end
  end
end