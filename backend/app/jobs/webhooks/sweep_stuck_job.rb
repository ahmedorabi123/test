module Webhooks
  class SweepStuckJob < ApplicationJob
    queue_as :webhooks

    def perform(cutoff: 10.minutes.ago)
      requeued = 0

      WebhookEvent.unprocessed.where("created_at < ?", cutoff).find_each do |event|
        Shopify::ProcessWebhookJob.perform_later(event.id)
        requeued += 1
      end

      requeued
    end
  end
end
