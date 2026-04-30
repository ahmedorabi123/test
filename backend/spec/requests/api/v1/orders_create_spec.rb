require "rails_helper"

RSpec.describe "Api::V1::Orders POST (manual order)", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:product) { create(:product) }
  let(:variant) { create(:variant, product: product, price: "25.00") }

  it "creates a manual order with line items" do
    expect {
      post "/api/v1/orders",
        params: {
          order: {
            source: "manual",
            customer_email: "walkin@x.com",
            customer_name: "Walk-in",
            line_items: [
              { variant_id: variant.id, title: "Item", quantity: 2, price: "25.00" }
            ]
          }
        }.to_json,
        headers: auth_headers(admin).merge("Content-Type" => "application/json")
    }.to change(Order, :count).by(1)
      .and change(OrderLineItem, :count).by(1)

    expect(response).to have_http_status(:created)
    expect(json_response[:data][:total_price]).to eq("50.0")
    expect(json_response[:data][:source]).to eq("manual")
    expect(json_response[:data][:financial_status]).to eq("pending")
  end

  it "marks order as paid when mark_paid=true" do
    post "/api/v1/orders",
      params: {
        order: {
          source: "showroom",
          mark_paid: true,
          line_items: [
            { variant_id: variant.id, quantity: 1, price: "99.99" }
          ]
        }
      }.to_json,
      headers: auth_headers(admin).merge("Content-Type" => "application/json")

    expect(response).to have_http_status(:created)
    expect(json_response[:data][:financial_status]).to eq("paid")
    expect(json_response[:data][:total_price]).to eq("99.99")
  end

  it "422 when line_items missing" do
    post "/api/v1/orders",
      params: { order: { source: "manual" } }.to_json,
      headers: auth_headers(admin).merge("Content-Type" => "application/json")
    expect(response).to have_http_status(:unprocessable_entity)
  end
end
