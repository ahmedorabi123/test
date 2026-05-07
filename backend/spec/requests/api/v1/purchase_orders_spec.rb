require "rails_helper"

RSpec.describe "Api::V1::PurchaseOrders", type: :request do
  let(:admin) { create(:user, :admin) }

  before do
    create(:account, code: "1200", name: "Inventory", account_type: "asset", normal_side: "debit")
    create(:account, code: "1300", name: "Recoverable VAT", account_type: "asset", normal_side: "debit")
    create(:account, code: "2000", name: "Accounts Payable", account_type: "liability", normal_side: "credit")
  end

  it "401 without auth" do
    get "/api/v1/purchase_orders"
    expect(response).to have_http_status(:unauthorized)
  end

  it "creates + receives a PO end-to-end" do
    warehouse = create(:warehouse)
    supplier  = create(:supplier)
    product   = create(:product)
    variant   = create(:variant, product: product, price: "10.00")

    post "/api/v1/purchase_orders",
      params: {
        purchase_order: {
          supplier_id: supplier.id,
          warehouse_id: warehouse.id,
          currency: "USD",
          line_items: [
            { variant_id: variant.id, quantity_ordered: 5, unit_cost: "4.00", title: "Item" }
          ]
        }
      }.to_json,
      headers: auth_headers(admin).merge("Content-Type" => "application/json")

    expect(response).to have_http_status(:created)
    po_id = json_response[:data][:id]
    li_id = json_response[:data][:line_items].first[:id]

    post "/api/v1/purchase_orders/#{po_id}/receive",
      params: {
        receipts: [{ line_item_id: li_id, quantity: 5 }]
      }.to_json,
      headers: auth_headers(admin).merge("Content-Type" => "application/json")

    expect(response).to have_http_status(:ok)
    expect(json_response[:data][:status]).to eq("received")
    expect(StockItem.find_by(variant: variant, warehouse: warehouse).quantity_on_hand).to eq(5)
  end

  it "lists POs" do
    create(:purchase_order)
    get "/api/v1/purchase_orders", headers: auth_headers(admin)
    expect(response).to have_http_status(:ok)
    expect(json_response[:data].size).to eq(1)
  end
end
