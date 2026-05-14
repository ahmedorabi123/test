require "rails_helper"

RSpec.describe "Api::V1::Orders POST (manual order)", type: :request do
  let(:admin) { create(:user, :admin) }
  let(:product) { create(:product) }
  let(:variant) { create(:variant, product: product, price: "25.00") }
  let(:warehouse) { create(:warehouse) }

  before do
    create(:stock_item, variant: variant, warehouse: warehouse, quantity_on_hand: 10)
  end

  it "creates a manual order with line items" do
    expect {
      post "/api/v1/orders",
        params: {
          order: {
            source: "manual",
            customer_email: "walkin@x.com",
            customer_name: "Walk-in",
            warehouse_id: warehouse.id,
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
          warehouse_id: warehouse.id,
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

  it "reserves Shopify-origin variants from non-Shopify showroom stock" do
    shopify_product = create(:product, :from_shopify)
    shopify_variant = create(:variant, :from_shopify, product: shopify_product, price: "25.00")
    showroom = create(:warehouse, kind: "consignment")
    stock_item = create(:stock_item, variant: shopify_variant, warehouse: showroom, quantity_on_hand: 6)

    post "/api/v1/orders",
      params: {
        order: {
          source: "showroom",
          warehouse_id: showroom.id,
          line_items: [
            { variant_id: shopify_variant.id, title: "Shopify Item", quantity: 2, price: "25.00" }
          ]
        }
      }.to_json,
      headers: auth_headers(admin).merge("Content-Type" => "application/json")

    expect(response).to have_http_status(:created), response.body
    expect(stock_item.reload.quantity_reserved).to eq(2)
  end

  it "rejects manual orders assigned to Shopify warehouses" do
    shopify_warehouse = create(:warehouse, shopify_location_id: 123456)

    post "/api/v1/orders",
      params: {
        order: {
          source: "manual",
          warehouse_id: shopify_warehouse.id,
          line_items: [
            { variant_id: variant.id, title: "Item", quantity: 1, price: "25.00" }
          ]
        }
      }.to_json,
      headers: auth_headers(admin).merge("Content-Type" => "application/json")

    expect(response).to have_http_status(:unprocessable_entity)
    expect(json_response.dig(:error, :detail)).to include("cannot use Shopify warehouses")
  end
end
