require "rails_helper"

RSpec.describe "Api::V1::ShowroomSales", type: :request do
  let(:admin) { create(:user, :admin) }
  let!(:ar)        { create(:account, code: "1100", name: "A/R",          account_type: "asset",   normal_side: "debit") }
  let!(:revenue)   { create(:account, code: "4000", name: "Sales Revenue", account_type: "revenue", normal_side: "credit") }
  let!(:tax)       { create(:account, code: "2200", name: "Tax",           account_type: "liability", normal_side: "credit") }
  let!(:shipping)  { create(:account, code: "4100", name: "Shipping",      account_type: "revenue", normal_side: "credit") }
  let!(:cogs)      { create(:account, code: "5000", name: "COGS",          account_type: "expense", normal_side: "debit") }
  let!(:inventory) { create(:account, code: "1200", name: "Inventory",     account_type: "asset",   normal_side: "debit") }

  let(:showroom) { create(:warehouse, kind: "consignment", code: "CAIRO-SR", currency: "EGP") }
  let(:product)  { create(:product) }
  let(:variant)  { create(:variant, product: product, price: 50.00, cost_per_item: 20.00) }

  before { create(:stock_item, variant: variant, warehouse: showroom, quantity_on_hand: 5) }

  it "posts a positive-only report and returns the order plus split summary" do
    post "/api/v1/showroom_sales",
         params: {
           warehouse_id: showroom.id, period: "2025-03",
           line_items: [{ variant_id: variant.id, quantity: 2, unit_price: "50.00" }]
         }, as: :json, headers: auth_headers(admin)

    expect(response).to have_http_status(:created)
    body = JSON.parse(response.body)["data"]
    expect(body["order"]).to be_present
    expect(body["reversal"]).to be_nil
    expect(body["sales_total"].to_d).to eq(100.to_d)
    expect(body["reversal_total"].to_d).to eq(0)
    # Legacy top-level keys preserved
    expect(body["order_number"]).to be_present
  end

  it "posts a mixed report with positive and negative lines" do
    v2 = create(:variant, product: product, price: 30.00, cost_per_item: 10.00)
    post "/api/v1/showroom_sales",
         params: {
           warehouse_id: showroom.id, period: "2025-04",
           line_items: [
             { variant_id: variant.id, quantity: 1, unit_price: "50.00" },
             { variant_id: v2.id, quantity: -1, unit_price: "30.00" }
           ]
         }, as: :json, headers: auth_headers(admin)

    expect(response).to have_http_status(:created)
    body = JSON.parse(response.body)["data"]
    expect(body["order"]).to be_present
    expect(body["reversal"]).to be_present
    expect(body["reversal_total"].to_d).to eq(30.to_d)
    expect(Refund.count).to eq(0)
  end

  it "accepts a reversal-only (negative) report and creates no Order/Refund/movement" do
    expect {
      post "/api/v1/showroom_sales",
           params: {
             warehouse_id: showroom.id, period: "2025-05",
             line_items: [{ variant_id: variant.id, quantity: -1, unit_price: "50.00" }]
           }, as: :json, headers: auth_headers(admin)
    }.to change { ShowroomReversal.count }.by(1)
      .and change { Order.count }.by(0)
      .and change { Refund.count }.by(0)
      .and change { StockMovement.count }.by(0)

    expect(response).to have_http_status(:created)
  end

  it "rejects re-posting the same (warehouse, period)" do
    post "/api/v1/showroom_sales",
         params: {
           warehouse_id: showroom.id, period: "2025-06",
           line_items: [{ variant_id: variant.id, quantity: 1, unit_price: "50.00" }]
         }, as: :json, headers: auth_headers(admin)
    expect(response).to have_http_status(:created)

    post "/api/v1/showroom_sales",
         params: {
           warehouse_id: showroom.id, period: "2025-06",
           line_items: [{ variant_id: variant.id, quantity: 1, unit_price: "50.00" }]
         }, as: :json, headers: auth_headers(admin)
    expect(response).to have_http_status(:unprocessable_content)
  end
end
