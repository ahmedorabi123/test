require "rails_helper"

RSpec.describe Shopify::ProcessWebhookJob, type: :job do
  let(:webhook_event) do
    WebhookEvent.create!(
      source:      "shopify",
      topic:       "orders/create",
      external_id: "wh-#{SecureRandom.hex(6)}",
      payload:     { "id" => 42, "updated_at" => "2026-04-21T10:00:00Z", "name" => "#1001" },
      received_at: Time.current
    )
  end

  it "marks the webhook event as processed" do
    described_class.new.perform(webhook_event.id)
    expect(webhook_event.reload).to be_processed
  end

  it "emits a DomainEvent into the outbox" do
    expect {
      described_class.new.perform(webhook_event.id)
    }.to change(DomainEvent, :count).by(1)

    ev = DomainEvent.last
    expect(ev.event_type).to eq("shopify_order_created")
    expect(ev.aggregate_type).to eq("shopify")
    expect(ev.aggregate_id).to eq("42")
  end

  it "is idempotent — skips when already processed" do
    webhook_event.mark_processed!
    expect {
      described_class.new.perform(webhook_event.id)
    }.not_to change(DomainEvent, :count)
  end

  it "marks unsupported topics as processed with error note (no retry)" do
    webhook_event.update!(topic: "orders/frobnicate")
    described_class.new.perform(webhook_event.id)
    ev = webhook_event.reload
    expect(ev).to be_processed
    expect(ev.error).to match(/Unsupported Shopify topic/)
  end

  it "marks failed and re-raises on unexpected errors" do
    allow(DomainEvent).to receive(:create!).and_raise(StandardError, "db blew up")
    expect {
      described_class.new.perform(webhook_event.id)
    }.to raise_error(StandardError, "db blew up")

    ev = webhook_event.reload
    expect(ev.error).to eq("db blew up")
    expect(ev.attempts).to eq(1)
  end

  describe "domain dispatch" do
    def make_event(topic, payload = { "id" => 1, "updated_at" => "2026-04-21T10:00:00Z" })
      WebhookEvent.create!(
        source: "shopify", topic: topic,
        external_id: "wh-#{SecureRandom.hex(6)}",
        payload: payload,
        received_at: Time.current
      )
    end

    it "dispatches products/create to Catalog::HandleShopifyProductJob" do
      ev = make_event("products/create", { "id" => 5, "updated_at" => "2026-04-21T10:00:00Z", "title" => "Tee" })
      expect { described_class.new.perform(ev.id) }
        .to have_enqueued_job(Catalog::HandleShopifyProductJob)
    end

    it "dispatches products/update to Catalog::HandleShopifyProductJob" do
      ev = make_event("products/update", { "id" => 5, "updated_at" => "2026-04-21T10:00:00Z", "title" => "Tee v2" })
      expect { described_class.new.perform(ev.id) }
        .to have_enqueued_job(Catalog::HandleShopifyProductJob)
    end

    it "dispatches inventory_levels/update to Inventory::HandleShopifyInventoryJob" do
      ev = make_event("inventory_levels/update", { "inventory_item_id" => 99, "available" => 10 })
      expect { described_class.new.perform(ev.id) }
        .to have_enqueued_job(Inventory::HandleShopifyInventoryJob)
    end

    it "dispatches inventory_levels/connect to Inventory::HandleShopifyInventoryJob" do
      ev = make_event("inventory_levels/connect", { "inventory_item_id" => 99, "location_id" => 1, "available" => 10 })
      expect { described_class.new.perform(ev.id) }
        .to have_enqueued_job(Inventory::HandleShopifyInventoryJob)
    end

    it "records inventory_items/update as a compliance no-op" do
      ev = make_event("inventory_items/update", { "id" => 88, "updated_at" => "2026-04-21T10:00:00Z" })
      expect { described_class.new.perform(ev.id) }
        .to have_enqueued_job(Shopify::ComplianceEventJob).with("inventory_items/update", hash_including("id" => 88))
    end

    it "dispatches orders/paid to Sales::HandleShopifyOrderJob" do
      ev = make_event("orders/paid", { "id" => 42, "updated_at" => "2026-04-21T10:00:00Z", "financial_status" => "paid" })
      expect { described_class.new.perform(ev.id) }
        .to have_enqueued_job(Sales::HandleShopifyOrderJob)
    end

    it "dispatches orders/cancelled to Sales::HandleShopifyOrderJob" do
      ev = make_event("orders/cancelled", { "id" => 43, "updated_at" => "2026-04-21T10:00:00Z", "cancelled_at" => "2026-04-21T10:00:00Z" })
      expect { described_class.new.perform(ev.id) }
        .to have_enqueued_job(Sales::HandleShopifyOrderJob)
    end

    it "dispatches orders/fulfilled to Sales::HandleShopifyOrderJob" do
      ev = make_event("orders/fulfilled", { "id" => 44, "updated_at" => "2026-04-21T10:00:00Z", "fulfillment_status" => "fulfilled" })
      expect { described_class.new.perform(ev.id) }
        .to have_enqueued_job(Sales::HandleShopifyOrderJob)
    end

    it "dispatches orders/edited to Sales::HandleShopifyOrderJob" do
      ev = make_event("orders/edited", { "id" => 45, "updated_at" => "2026-04-21T10:00:00Z" })
      expect { described_class.new.perform(ev.id) }
        .to have_enqueued_job(Sales::HandleShopifyOrderJob)
    end

    it "dispatches refunds/create to Sales::HandleShopifyRefundJob" do
      ev = make_event("refunds/create", { "id" => 101, "order_id" => 42, "updated_at" => "2026-04-21T10:00:00Z" })
      expect { described_class.new.perform(ev.id) }
        .to have_enqueued_job(Sales::HandleShopifyRefundJob)
    end

    it "dispatches fulfillments/create to Shipping::HandleShopifyFulfillmentJob" do
      ev = make_event("fulfillments/create", { "id" => 55, "order_id" => 42, "updated_at" => "2026-04-21T10:00:00Z" })
      expect { described_class.new.perform(ev.id) }
        .to have_enqueued_job(Shipping::HandleShopifyFulfillmentJob)
    end

    it "dispatches fulfillments/update to Shipping::HandleShopifyFulfillmentJob" do
      ev = make_event("fulfillments/update", { "id" => 55, "order_id" => 42, "updated_at" => "2026-04-21T10:00:00Z" })
      expect { described_class.new.perform(ev.id) }
        .to have_enqueued_job(Shipping::HandleShopifyFulfillmentJob)
    end

    it "dispatches fulfillments/cancelled to Shipping::HandleShopifyFulfillmentJob" do
      ev = make_event("fulfillments/cancelled", { "id" => 55, "order_id" => 42, "updated_at" => "2026-04-21T10:00:00Z" })
      expect { described_class.new.perform(ev.id) }
        .to have_enqueued_job(Shipping::HandleShopifyFulfillmentJob)
    end

    it "dispatches customers/create to Crm::HandleShopifyCustomerJob" do
      ev = make_event("customers/create", { "id" => 77, "email" => "a@b.c", "updated_at" => "2026-04-21T10:00:00Z" })
      expect { described_class.new.perform(ev.id) }
        .to have_enqueued_job(Crm::HandleShopifyCustomerJob)
    end

    it "dispatches customers/update to Crm::HandleShopifyCustomerJob" do
      ev = make_event("customers/update", { "id" => 77, "email" => "a@b.c", "updated_at" => "2026-04-21T10:00:00Z" })
      expect { described_class.new.perform(ev.id) }
        .to have_enqueued_job(Crm::HandleShopifyCustomerJob)
    end

    it "records customers/redact as a compliance no-op" do
      ev = make_event("customers/redact", { "shop_id" => 1, "customer" => { "id" => 77 } })
      expect { described_class.new.perform(ev.id) }
        .to have_enqueued_job(Shopify::ComplianceEventJob).with("customers/redact", hash_including("shop_id" => 1))
    end

    it "uses the inbound-only pipeline when SHOPIFY_PIPELINE_V2=true" do
      original = ENV["SHOPIFY_PIPELINE_V2"]
      ENV["SHOPIFY_PIPELINE_V2"] = "true"
      ev = make_event("refunds/create", { "id" => 101, "order_id" => 42, "updated_at" => "2026-04-21T10:00:00Z" })

      expect { described_class.new.perform(ev.id) }
        .to have_enqueued_job(Sales::HandleShopifyRefundJob)
    ensure
      ENV["SHOPIFY_PIPELINE_V2"] = original
    end
  end
end
