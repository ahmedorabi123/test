module Shopify
  # Processes a persisted WebhookEvent: normalizes it into a domain event
  # and hands off to whatever domain cares. For Phase 1 it just marks
  # the event processed. Later phases will add actual domain handlers.
  class ProcessWebhookJob < ApplicationJob
    queue_as :webhooks

    # Retry transient failures; giveup after max attempts.
    retry_on StandardError, wait: :polynomially_longer, attempts: 5

    def perform(webhook_event_id)
      event = WebhookEvent.find(webhook_event_id)
      return if event.processed?

      begin
        normalized = ::Shopify::EventNormalizer.normalize(
          topic:   event.topic,
          payload: event.payload
        )
      rescue ::Shopify::EventNormalizer::UnsupportedTopicError => e
        # We accept & ACK unsupported topics at the controller layer, but if
        # one slips through, mark it processed-with-note so we don't retry.
        event.update!(processed_at: Time.current, error: e.message)
        return
      end

      # Phase 1 stop here — dispatch to domain handlers in later phases.
      # Emit into the outbox so domains can subscribe.
      DomainEvent.create!(
        event_type:  normalized[:type],
        aggregate_type: "shopify",
        aggregate_id: normalized[:external_id],
        payload:     normalized[:data],
        occurred_at: normalized[:occurred_at]
      )

      dispatch_to_domain(normalized)

      event.mark_processed!
    rescue => e
      event.mark_failed!(e.message)
      raise
    end

    private

    def dispatch_to_domain(normalized)
      case normalized[:type]
      when :shopify_product_created, :shopify_product_updated
        Catalog::HandleShopifyProductJob.perform_later(normalized[:data])
      when :shopify_inventory_updated
        Inventory::HandleShopifyInventoryJob.perform_later(normalized[:data])
      when :shopify_order_created, :shopify_order_updated, :shopify_order_paid,
           :shopify_order_cancelled, :shopify_order_fulfilled
        Sales::HandleShopifyOrderJob.perform_later(normalized[:data])
      when :shopify_refund_created
        Sales::HandleShopifyRefundJob.perform_later(normalized[:data])
      when :shopify_fulfillment_created, :shopify_fulfillment_updated
        Shipping::HandleShopifyFulfillmentJob.perform_later(normalized[:data])
      when :shopify_customer_created, :shopify_customer_updated
        Crm::HandleShopifyCustomerJob.perform_later(normalized[:data])
      end
    end
  end
end
