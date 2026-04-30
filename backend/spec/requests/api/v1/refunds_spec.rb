require "rails_helper"

RSpec.describe "Api::V1::Refunds", type: :request do
  let(:admin) { create(:user, :admin) }

  it "401 without auth" do
    get "/api/v1/refunds"
    expect(response).to have_http_status(:unauthorized)
  end

  it "lists refunds for admin" do
    order = create(:order, total_price: 100)
    create(:refund, order: order, amount: 30)
    create(:refund, order: order, amount: 100)
    get "/api/v1/refunds", headers: auth_headers(admin)
    expect(response).to have_http_status(:ok)
    expect(json_response[:data].size).to eq(2)
    partials = json_response[:data].map { |r| r[:partial] }
    expect(partials).to include(true, false)
  end
end
