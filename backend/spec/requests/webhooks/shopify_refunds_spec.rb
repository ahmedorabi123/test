require "rails_helper"

# Refunds are wired through the same HMAC pipeline as other webhooks. This
# spec just nails down that the "refunds/create" topic is on the supported
# allow-list and triggers the refund job (regardless of pipeline_v2 flag).
RSpec.describe "Webhooks::Shopify refunds/create", type: :request do
  let(:secret)   { "test-hmac-secret" }
  let(:payload)  { { id: 9876, order_id: 4242, transactions: [], refund_line_items: [] } }
  let(:raw_body) { payload.to_json }

  before do
    ENV["SHOPIFY_API_SECRET"]   = secret
    ENV["WEBHOOKS_HMAC_BYPASS"] = "false"
  end

  def hmac_for(body)
    Base64.strict_encode64(OpenSSL::HMAC.digest("sha256", secret, body))
  end

  def post_refund
    post "/webhooks/shopify/refunds/create",
         params:  raw_body,
         headers: {
           "Content-Type"          => "application/json",
           "X-Shopify-Hmac-Sha256" => hmac_for(raw_body),
           "X-Shopify-Topic"       => "refunds/create",
           "X-Shopify-Webhook-Id"  => "ref-#{SecureRandom.hex(4)}"
         }
  end

  it "persists the webhook and enqueues the processor" do
    expect {
      post_refund
    }.to change(WebhookEvent, :count).by(1)
      .and have_enqueued_job(Shopify::ProcessWebhookJob)

    expect(response).to have_http_status(:accepted)
    event = WebhookEvent.last
    expect(event.topic).to eq("refunds/create")
  end

  describe "normalizer" do
    it "maps refunds/create to :shopify_refund_created" do
      norm = Shopify::EventNormalizer.normalize(topic: "refunds/create", payload: payload.deep_stringify_keys)
      expect(norm[:type]).to eq(:shopify_refund_created)
    end
  end

  describe "pipeline registry" do
    it "dispatches :shopify_refund_created to :refund" do
      expect(Shopify::Pipeline::Registry.handler_for(:shopify_refund_created)).to eq(:refund)
    end
  end
end
