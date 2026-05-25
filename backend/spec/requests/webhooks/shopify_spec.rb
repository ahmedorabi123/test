require "rails_helper"

RSpec.describe "Webhooks::Shopify", type: :request do
  let(:secret)   { "test-hmac-secret" }
  let(:payload)  { { id: 12345, name: "#1001", updated_at: "2026-04-21T10:00:00Z" } }
  let(:raw_body) { payload.to_json }

  before do
    ENV["SHOPIFY_API_SECRET"]     = secret
    ENV["WEBHOOKS_HMAC_BYPASS"]   = "false"
  end

  def hmac_for(body)
    Base64.strict_encode64(OpenSSL::HMAC.digest("sha256", secret, body))
  end

  def post_webhook(topic:, body: raw_body, signature: hmac_for(body), webhook_id: "hook-#{SecureRandom.hex(4)}")
    post "/webhooks/shopify/#{topic}",
         params: body,
         headers: {
           "Content-Type"             => "application/json",
           "X-Shopify-Hmac-Sha256"    => signature,
           "X-Shopify-Topic"          => topic,
           "X-Shopify-Webhook-Id"     => webhook_id
         }
  end

  describe "happy path" do
    it "persists the webhook, enqueues ProcessWebhookJob, and returns 202" do
      expect {
        post_webhook(topic: "orders/create")
      }.to change(WebhookEvent, :count).by(1)
        .and have_enqueued_job(Shopify::ProcessWebhookJob)

      expect(response).to have_http_status(:accepted)
      event = WebhookEvent.last
      expect(event.source).to eq("shopify")
      expect(event.topic).to eq("orders/create")
      expect(event.payload["id"]).to eq(12345)
    end
  end

  describe "security" do
    it "rejects invalid HMAC with 401" do
      post_webhook(topic: "orders/create", signature: "bogus-signature")
      expect(response).to have_http_status(:unauthorized)
      expect(WebhookEvent.count).to eq(0)
    end

    it "rejects missing HMAC header" do
      post_webhook(topic: "orders/create", signature: "")
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "idempotency" do
    it "acknowledges duplicate Webhook-Id without creating a second record" do
      id = "wh-dup-#{SecureRandom.hex(4)}"
      post_webhook(topic: "orders/create", webhook_id: id)
      expect(response).to have_http_status(:accepted)

      expect {
        post_webhook(topic: "orders/create", webhook_id: id)
      }.not_to change(WebhookEvent, :count)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["status"]).to eq("duplicate")
    end
  end

  describe "unsupported topics" do
    it "returns 200 with ignored status without persisting" do
      expect {
        post_webhook(topic: "orders/frobnicate")
      }.not_to change(WebhookEvent, :count)

      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["status"]).to eq("ignored")
    end
  end

  describe "malformed JSON" do
    it "returns 400" do
      bad_body = "{not json"
      post_webhook(topic: "orders/create", body: bad_body, signature: hmac_for(bad_body))
      expect(response).to have_http_status(:bad_request)
    end
  end

  describe "supported topics" do
    %w[
      orders/create orders/updated orders/paid orders/cancelled orders/edited orders/fulfilled orders/partially_fulfilled
      products/create products/update
      inventory_items/create inventory_items/update inventory_items/delete
      inventory_levels/connect inventory_levels/disconnect inventory_levels/update
      fulfillments/cancelled
      customers/data_request customers/redact shop/redact app/uninstalled
    ].each do |topic|
      it "accepts #{topic} and enqueues the job" do
        expect {
          post_webhook(topic: topic)
        }.to change(WebhookEvent, :count).by(1)
          .and have_enqueued_job(Shopify::ProcessWebhookJob)

        expect(response).to have_http_status(:accepted)
        expect(WebhookEvent.last.topic).to eq(topic)
      end
    end

    it "accepts refunds/create and persists the webhook" do
      expect {
        post_webhook(topic: "refunds/create")
      }.to change(WebhookEvent, :count).by(1)

      expect(response).to have_http_status(:accepted)
      expect(WebhookEvent.last.topic).to eq("refunds/create")
    end
  end

  describe "payload content" do
    it "stores the parsed JSON payload on the event" do
      product_payload = { id: 77_777, title: "Beach Towel", updated_at: "2026-04-21T10:00:00Z" }.to_json
      post_webhook(topic: "products/create", body: product_payload, signature: hmac_for(product_payload))
      expect(response).to have_http_status(:accepted)
      expect(WebhookEvent.last.payload["title"]).to eq("Beach Towel")
    end

    it "uses the X-Shopify-Webhook-Id header as the external_id for deduplication" do
      uid = "unique-webhook-abc123"
      post_webhook(topic: "orders/create", webhook_id: uid)
      expect(WebhookEvent.last.external_id).to eq(uid)
    end
  end
end
