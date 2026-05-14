require "rails_helper"

RSpec.describe "Api::V1::Fulfillments", type: :request do
  let(:admin) { create(:user, :admin) }

  it "401 without auth" do
    get "/api/v1/fulfillments"
    expect(response).to have_http_status(:unauthorized)
  end

  it "lists fulfillments for admin" do
    create(:fulfillment, tracking_company: "Bosta")
    create(:fulfillment, tracking_company: "DHL")
    get "/api/v1/fulfillments", headers: auth_headers(admin)
    expect(response).to have_http_status(:ok)
    expect(json_response[:data].size).to eq(2)
  end

  it "filters by carrier (case-insensitive)" do
    create(:fulfillment, tracking_company: "Bosta")
    create(:fulfillment, tracking_company: "DHL")
    get "/api/v1/fulfillments", params: { carrier: "bosta" }, headers: auth_headers(admin)
    expect(json_response[:data].size).to eq(1)
    expect(json_response[:data].first[:carrier]).to eq("bosta")
  end

  it "includes parent order Shopify lock metadata" do
    order = create(:order, :from_shopify)
    fulfillment = create(:fulfillment, order: order)

    get "/api/v1/fulfillments/#{fulfillment.id}", headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    order_summary = json_response.dig(:data, :order)
    expect(order_summary).to include(
      source: "shopify",
      shopify_order_id: order.shopify_order_id,
      read_only_origin: true
    )
  end
end
