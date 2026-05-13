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

  it "allows approved transitions for Shopify-origin orders" do
    shopify_order = create(:order, :from_shopify)

    post "/api/v1/orders/#{shopify_order.id}/transition", params: { to: "paid" }, headers: headers

    expect(response).to have_http_status(:ok)
    expect(shopify_order.reload.financial_status).to eq("paid")

    post "/api/v1/orders/#{shopify_order.id}/transition", params: { to: "fulfilled" }, headers: headers

    expect(response).to have_http_status(:ok)
    expect(shopify_order.reload.status).to eq("fulfilled")
  end

  it "rejects non-whitelisted transitions for Shopify-origin orders" do
    shopify_order = create(:order, :from_shopify)

    post "/api/v1/orders/#{shopify_order.id}/transition", params: { to: "processing" }, headers: headers

    expect(response).to have_http_status(:unprocessable_entity)
    expect(json_response.dig(:error, :type)).to eq("read_only_shopify_resource")
    expect(shopify_order.reload.status).to eq("pending")
  end

  it "updates Shopify-origin order notes and delivery status only" do
    shopify_order = create(:order, :from_shopify)

    patch "/api/v1/orders/#{shopify_order.id}",
          params: { order: { notes: "Packed locally", delivery_status: "in_transit" } },
          as: :json,
          headers: headers

    expect(response).to have_http_status(:ok)
    expect(shopify_order.reload.notes).to eq("Packed locally")
    expect(shopify_order.last_delivery_status).to eq("in_transit")
  end

  it "rejects non-whitelisted Shopify-origin order updates" do
    shopify_order = create(:order, :from_shopify, customer_email: "shop@example.com")

    patch "/api/v1/orders/#{shopify_order.id}",
          params: { order: { customer_email: "erp@example.com" } },
          as: :json,
          headers: headers

    expect(response).to have_http_status(:unprocessable_entity)
    expect(json_response.dig(:error, :type)).to eq("read_only_shopify_resource")
    expect(shopify_order.reload.customer_email).to eq("shop@example.com")
  end
end
