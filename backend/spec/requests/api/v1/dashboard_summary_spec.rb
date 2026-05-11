require "rails_helper"

RSpec.describe "Api::V1::Dashboard summary", type: :request do
  let(:admin) { create(:user, :admin) }

  before do
    [
      ["1100", "Accounts Receivable", "asset",     "debit"],
      ["1200", "Inventory Asset",     "asset",     "debit"],
      ["4000", "Sales Revenue",       "revenue",   "credit"],
      ["5000", "COGS",                "expense",   "debit"]
    ].each do |code, name, type, side|
      Account.find_or_create_by!(code: code) do |a|
        a.name = name; a.account_type = type; a.normal_side = side
      end
    end
  end

  it "requires auth" do
    get "/api/v1/dashboard/summary"
    expect(response).to have_http_status(:unauthorized)
  end

  it "returns the summary payload for admin" do
    create(:order, placed_at: 2.days.ago, total_price: 100.00, status: "pending", financial_status: "paid")
    create(:order, placed_at: 5.days.ago, total_price: 50.00,  status: "fulfilled", financial_status: "paid")

    get "/api/v1/dashboard/summary", params: { window: 30 }, headers: auth_headers(admin)
    expect(response).to have_http_status(:ok)

    body = json_response[:data]
    expect(body[:window_days]).to eq(30)
    expect(body[:kpis]).to include(:revenue, :orders_count, :ar_outstanding,
                                   :pending_shipments, :pending_refunds,
                                   :low_stock_count, :orders_pending)
    expect(body[:revenue_trend]).to be_an(Array)
    expect(body[:orders_by_status]).to be_a(Hash)
    expect(body[:delivery_breakdown]).to be_a(Hash)
    expect(body[:gross_margin]).to include(:revenue, :cogs, :margin, :margin_pct)
    expect(body[:recent_activity]).to be_an(Array)
  end

  it "caps the window to 365 days" do
    get "/api/v1/dashboard/summary", params: { window: 10_000 }, headers: auth_headers(admin)
    expect(response).to have_http_status(:ok)
    expect(json_response[:data][:window_days]).to be <= 365
  end
end
