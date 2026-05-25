module Webhooks
  class SweepStuckJob < ApplicationJob
    queue_as :webhooks

    # Stop re-enqueuing events that have failed this many times. The original
    # webhook is still visible in WebhookEvent.failed for the diagnose rake,
    # plus we emit an AuditLog so admins can see something stopped retrying.
    MAX_ATTEMPTS = (ENV["WEBHOOK_MAX_ATTEMPTS"].presence || 10).to_i

    def perform(cutoff: 10.minutes.ago)
      requeued = 0
      dead     = 0

      WebhookEvent.unprocessed.where("created_at < ?", cutoff).find_each do |event|
        if event.attempts.to_i >= MAX_ATTEMPTS
          mark_dead(event)
          dead += 1
          next
        end

        Shopify::ProcessWebhookJob.perform_later(event.id)
        requeued += 1
      end

      { requeued: requeued, dead: dead }
    end

    private

    def mark_dead(event)
      # Idempotent: only audit once. Subsequent sweeps will skip because the
      # error column already starts with "DEAD:".
      return if event.error.to_s.start_with?("DEAD:")

      event.update_columns(
        error:      "DEAD: max attempts (#{MAX_ATTEMPTS}) exceeded - #{event.error}",
        updated_at: Time.current
      )

      return unless defined?(AuditLog)

      AuditLog.create!(
        action:       "webhook.dead",
        subject_type: "WebhookEvent",
        subject_id:   event.id,
        diff:         {
          webhook_event_id: event.id,
          topic:            event.topic,
          attempts:         event.attempts,
          last_error:       event.error.to_s.sub(/^DEAD: /, "")
        },
        occurred_at:  Time.current
      )
    rescue => e
      Rails.logger.warn("[webhooks/sweep] mark_dead failed: #{e.class}: #{e.message}")
    end
  end
end
