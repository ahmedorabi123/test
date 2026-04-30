require "rails_helper"

RSpec.describe "Api::V1::Warehouses", type: :request do
  let(:admin) { create(:user, :admin) }

  describe "GET /api/v1/warehouses" do
    it "401 without auth" do
      get "/api/v1/warehouses"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns list for admin" do
      create_list(:warehouse, 2)
      get "/api/v1/warehouses", headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["data"].size).to eq(2)
    end
  end

  describe "POST /api/v1/warehouses" do
    it "creates a warehouse" do
      post "/api/v1/warehouses",
           params: { warehouse: { name: "East Coast DC", code: "EC-DC-01", address: "123 Main St" } },
           as: :json,
           headers: auth_headers(admin)
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["data"]["code"]).to eq("EC-DC-01")
    end

    it "422 on duplicate code" do
      create(:warehouse, code: "DUP-01")
      post "/api/v1/warehouses",
           params: { warehouse: { name: "X", code: "dup-01" } },
           as: :json,
           headers: auth_headers(admin)
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /api/v1/warehouses/:id" do
    it "updates warehouse name" do
      wh = create(:warehouse, name: "Old Name")
      patch "/api/v1/warehouses/#{wh.id}",
            params: { warehouse: { name: "New Name" } },
            as: :json,
            headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(wh.reload.name).to eq("New Name")
    end
  end

  describe "DELETE /api/v1/warehouses/:id" do
    it "destroys empty warehouse" do
      wh = create(:warehouse)
      delete "/api/v1/warehouses/#{wh.id}", headers: auth_headers(admin)
      expect(response).to have_http_status(:no_content)
    end
  end
end

RSpec.describe "Api::V1::StockItems", type: :request do
  let(:admin) { create(:user, :admin) }

  describe "GET /api/v1/stock_items" do
    it "returns stock items, filterable by warehouse" do
      wh1 = create(:warehouse)
      wh2 = create(:warehouse)
      create(:stock_item, warehouse: wh1)
      create(:stock_item, warehouse: wh2)
      get "/api/v1/stock_items", params: { warehouse_id: wh1.id }, headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["data"].size).to eq(1)
    end

    it "filters low stock" do
      create(:stock_item, quantity_on_hand: 2, quantity_reserved: 0, low_stock_threshold: 5)
      create(:stock_item, quantity_on_hand: 20, quantity_reserved: 0, low_stock_threshold: 5)
      get "/api/v1/stock_items", params: { low_stock: "true" }, headers: auth_headers(admin)
      expect(JSON.parse(response.body)["data"].size).to eq(1)
    end
  end

  describe "PATCH /api/v1/stock_items/:id" do
    it "adjusts quantity and creates a movement" do
      si = create(:stock_item, quantity_on_hand: 10)
      expect {
        patch "/api/v1/stock_items/#{si.id}",
              params: { stock_item: { quantity_on_hand: 25 } },
              as: :json,
              headers: auth_headers(admin)
      }.to change(StockMovement, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(si.reload.quantity_on_hand).to eq(25)
      expect(StockMovement.last.delta).to eq(15)
      expect(StockMovement.last.reason).to eq("adjusted")
    end
  end
end
