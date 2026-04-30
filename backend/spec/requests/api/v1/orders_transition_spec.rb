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
end
