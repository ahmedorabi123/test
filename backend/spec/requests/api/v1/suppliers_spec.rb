require "rails_helper"

RSpec.describe "Api::V1::Suppliers", type: :request do
  let(:admin) { create(:user, :admin) }

  it "creates suppliers with generated code, lead time, and on_hold status" do
    post "/api/v1/suppliers",
      params: {
        supplier: {
          name: "North Cairo Textiles",
          email: "orders@example.com",
          currency: "EGP",
          status: "on_hold",
          lead_time_days: 14,
          address: { city: "Cairo", country: "EG" },
          payment_terms: { net_days: 30, notes: "Bank transfer" }
        }
      }.to_json,
      headers: auth_headers(admin).merge("Content-Type" => "application/json")

    expect(response).to have_http_status(:created)
    supplier = Supplier.last
    expect(supplier.supplier_code).to be_present
    expect(supplier.status).to eq("on_hold")
    expect(supplier.lead_time_days).to eq(14)
    expect(json_response[:data][:supplier_code]).to eq(supplier.supplier_code)
  end

  it "returns balance summary on show" do
    supplier = create(:supplier)
    create(:purchase_order, supplier: supplier, status: "ordered", total: "100.00")
    create(:purchase_order, supplier: supplier, status: "received", total: "70.00")
    create(:purchase_order, supplier: supplier, status: "cancelled", total: "50.00")

    get "/api/v1/suppliers/#{supplier.id}", headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    summary = json_response[:data][:balance_summary]
    expect(summary[:purchase_orders_count]).to eq(3)
    expect(summary[:total_ordered]).to eq("170.0")
    expect(summary[:received_total]).to eq("70.0")
    expect(summary[:open_total]).to eq("100.0")
  end

  it "lists purchase orders for a supplier" do
    supplier = create(:supplier)
    other_supplier = create(:supplier)
    po = create(:purchase_order, supplier: supplier)
    create(:purchase_order, supplier: other_supplier)

    get "/api/v1/suppliers/#{supplier.id}/purchase_orders", headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    expect(json_response[:data].map { |row| row[:id] }).to eq([ po.id ])
  end
end
