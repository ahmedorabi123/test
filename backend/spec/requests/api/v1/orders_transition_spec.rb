require "rails_helper"

RSpec.describe "POST /api/v1/orders/:id/transition", type: :request do
  let(:user) { create(:user, :admin) }
  let(:headers) { auth_headers(user) }
  let(:order) { create(:order) }

  it "transitions order status" do
    post "/api/v1/orders/#{order.id}/transition", params: { to: "processing" }, headers: headers
    expect(response).to have_http_status(:ok)
    expect(order.reload.status).to eq("processing")
  end

  it "returns 422 on illegal transition" do
    order.update!(status: "cancelled", cancelled_at: Time.current)
    post "/api/v1/orders/#{order.id}/transition", params: { to: "processing" }, headers: headers
    expect(response).to have_http_status(:unprocessable_content).or have_http_status(:unprocessable_entity)
  end

  it "returns 400 when 'to' missing" do
    post "/api/v1/orders/#{order.id}/transition", params: {}, headers: headers
    expect(response).to have_http_status(:bad_request)
  end

  it "rejects all transitions for Shopify-origin orders" do
    shopify_order = create(:order, :from_shopify)

    post "/api/v1/orders/#{shopify_order.id}/transition", params: { to: "paid" }, headers: headers

    expect(response).to have_http_status(:locked)
    expect(json_response.dig(:error, :type)).to eq("read_only_shopify_resource")
    expect(shopify_order.reload.financial_status).to eq("pending")
  end

  it "rejects Shopify-origin order updates" do
    shopify_order = create(:order, :from_shopify)

    patch "/api/v1/orders/#{shopify_order.id}",
          params: { order: { notes: "Packed locally", delivery_status: "in_transit" } },
          as: :json,
          headers: headers

    expect(response).to have_http_status(:locked)
    expect(json_response.dig(:error, :type)).to eq("read_only_shopify_resource")
    expect(shopify_order.reload.notes).to be_nil
    expect(shopify_order.last_delivery_status).to be_nil
  end
end
