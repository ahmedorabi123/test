require "rails_helper"

RSpec.describe Webhooks::SweepStuckJob, type: :job do
  it "re-enqueues old unprocessed webhook events" do
    old_event = WebhookEvent.create!(
      source: "shopify",
      topic: "orders/create",
      external_id: "old-#{SecureRandom.hex(4)}",
      payload: { "id" => 123, "updated_at" => "2026-05-10T10:00:00Z" },
      received_at: 20.minutes.ago,
      created_at: 20.minutes.ago,
      updated_at: 20.minutes.ago
    )
    recent_event = WebhookEvent.create!(
      source: "shopify",
      topic: "orders/create",
      external_id: "recent-#{SecureRandom.hex(4)}",
      payload: { "id" => 124, "updated_at" => "2026-05-10T10:00:00Z" },
      received_at: Time.current
    )

    expect {
      described_class.new.perform(cutoff: 10.minutes.ago)
    }.to have_enqueued_job(Shopify::ProcessWebhookJob).with(old_event.id).once

    expect(enqueued_jobs.map { |job| job[:args] }).not_to include([recent_event.id])
  end
end
