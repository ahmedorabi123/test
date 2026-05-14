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

  it "creates + receives a PO end-to-end (Phase 1: inventory-only)" do
    warehouse = create(:warehouse)
    supplier  = create(:supplier)
    product   = create(:product)
    variant   = create(:variant, product: product, price: "10.00")

    expect {
      post "/api/v1/purchase_orders",
        params: {
          purchase_order: {
            supplier_id: supplier.id,
            warehouse_id: warehouse.id,
            currency: "USD",
            line_items: [
              { variant_id: variant.id, quantity_ordered: 5, title: "Item" }
            ]
          }
        }.to_json,
        headers: auth_headers(admin).merge("Content-Type" => "application/json")
    }.to change { AuditLog.where(action: "purchase_order.created").count }.by(1)

    expect(response).to have_http_status(:created)
    po_id = json_response[:data][:id]
    li_id = json_response[:data][:line_items].first[:id]

    expect {
      post "/api/v1/purchase_orders/#{po_id}/receive",
        params: {
          receipts: [ { line_item_id: li_id, quantity: 5 } ]
        }.to_json,
        headers: auth_headers(admin).merge("Content-Type" => "application/json")
    }.to change { AuditLog.where(action: "purchase_order.received").count }.by(1)
      .and(change { JournalEntry.count }.by(0))

    expect(response).to have_http_status(:ok)
    expect(json_response[:data][:status]).to eq("received")
    expect(StockItem.find_by(variant: variant, warehouse: warehouse).quantity_on_hand).to eq(5)
    # Phase 1: variant.last_purchase_cost is intentionally NOT updated by receives.
    expect(variant.reload.last_purchase_cost).to be_nil
  end

  it "rejects POs against non-factory suppliers" do
    warehouse = create(:warehouse)
    supplier  = create(:supplier, kind: "material")
    variant   = create(:variant, price: "10.00")

    post "/api/v1/purchase_orders",
      params: {
        purchase_order: {
          supplier_id: supplier.id,
          warehouse_id: warehouse.id,
          currency: "USD",
          line_items: [ { variant_id: variant.id, quantity_ordered: 1, title: "Item" } ]
        }
      }.to_json,
      headers: auth_headers(admin).merge("Content-Type" => "application/json")

    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to include("factory supplier")
  end

  it "ignores unit_cost in payload and stores zeros on the line" do
    warehouse = create(:warehouse)
    supplier  = create(:supplier)
    variant   = create(:variant, cost: "7.25", last_purchase_cost: "5.00", price: "99.00")

    post "/api/v1/purchase_orders",
      params: {
        purchase_order: {
          supplier_id: supplier.id,
          warehouse_id: warehouse.id,
          currency: "USD",
          line_items: [
            { variant_id: variant.id, quantity_ordered: 3, unit_cost: "12.99", title: "Item" }
          ]
        }
      }.to_json,
      headers: auth_headers(admin).merge("Content-Type" => "application/json")

    expect(response).to have_http_status(:created)
    line_item = json_response[:data][:line_items].first
    expect(line_item[:unit_cost].to_d).to eq(0.to_d)
    expect(line_item[:subtotal].to_d).to eq(0.to_d)
    expect(json_response[:data][:total].to_d).to eq(0.to_d)
  end

  it "lists POs" do
    create(:purchase_order)
    get "/api/v1/purchase_orders", headers: auth_headers(admin)
    expect(response).to have_http_status(:ok)
    expect(json_response[:data].size).to eq(1)
  end
end
