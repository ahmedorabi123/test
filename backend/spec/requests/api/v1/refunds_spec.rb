require "rails_helper"

RSpec.describe "Api::V1::Refunds", type: :request do
  let(:admin) { create(:user, :admin) }

  it "is not routed in Phase 1" do
    get "/api/v1/refunds"
    expect(response).to have_http_status(:not_found)
  end

  it "does not expose refund listing for admins" do
    order = create(:order, total_price: 100)
    create(:refund, order: order, amount: 30)
    create(:refund, order: order, amount: 100)
    get "/api/v1/refunds", headers: auth_headers(admin)
    expect(response).to have_http_status(:not_found)
  end
end
