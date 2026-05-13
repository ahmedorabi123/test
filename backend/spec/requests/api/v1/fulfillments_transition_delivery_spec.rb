require "rails_helper"

RSpec.describe "Api::V1::Fulfillments transition_delivery", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:fulfillment) do
    create(:fulfillment, tracking_company: "Bosta", delivery_status: "pending")
  end

  it "requires auth" do
    post "/api/v1/fulfillments/#{fulfillment.id}/transition_delivery", params: { to: "in_transit" }
    expect(response).to have_http_status(:unauthorized)
  end

  it "transitions pending → in_transit" do
    post "/api/v1/fulfillments/#{fulfillment.id}/transition_delivery",
         params: { to: "in_transit" }, headers: auth_headers(admin)
    expect(response).to have_http_status(:ok)
    expect(json_response[:data][:delivery_status]).to eq("in_transit")
  end

  it "returns 422 on illegal transition" do
    fulfillment.update!(delivery_status: "delivered", delivered_at: Time.current)
    post "/api/v1/fulfillments/#{fulfillment.id}/transition_delivery",
         params: { to: "in_transit" }, headers: auth_headers(admin)
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "is idempotent on same target" do
    fulfillment.update!(delivery_status: "delivered", delivered_at: Time.current)
    post "/api/v1/fulfillments/#{fulfillment.id}/transition_delivery",
         params: { to: "delivered" }, headers: auth_headers(admin)
    expect(response).to have_http_status(:ok)
  end

  it "allows delivery transitions for Shopify-origin fulfillments" do
    Shopify::Origin.without_read_only do
      fulfillment.update!(shopify_fulfillment_id: 123456)
    end

    post "/api/v1/fulfillments/#{fulfillment.id}/transition_delivery",
         params: { to: "in_transit" }, headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    expect(fulfillment.reload.delivery_status).to eq("in_transit")
    expect(fulfillment.in_transit_at).to be_present
  end
end
