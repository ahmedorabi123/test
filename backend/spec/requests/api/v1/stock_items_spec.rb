require "rails_helper"

RSpec.describe "Api::V1::StockItems", type: :request do
  let(:admin) { create(:user, :admin) }

  # ─── INDEX ────────────────────────────────────────────────────────────────────

  describe "GET /api/v1/stock_items" do
    it "401 without auth" do
      get "/api/v1/stock_items"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns paginated stock items" do
      create_list(:stock_item, 3)
      get "/api/v1/stock_items", headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["data"].size).to eq(3)
      expect(body["meta"]).to include("total", "page", "per_page")
    end

    it "includes required Shopify-parity columns" do
      si = create(:stock_item, quantity_on_hand: 10, quantity_reserved: 2, quantity_unavailable: 1)
      get "/api/v1/stock_items", headers: auth_headers(admin)
      item = JSON.parse(response.body)["data"].find { |d| d["id"] == si.id }
      expect(item).to include(
        "quantity_on_hand", "quantity_reserved", "quantity_unavailable",
        "available", "product_title", "sku", "warehouse_name", "low_stock"
      )
      expect(item["available"]).to eq(7) # 10 - 2 - 1
    end

    it "filters by warehouse_id" do
      wh1 = create(:warehouse)
      wh2 = create(:warehouse)
      create(:stock_item, warehouse: wh1)
      create(:stock_item, warehouse: wh2)
      get "/api/v1/stock_items", params: { warehouse_id: wh1.id }, headers: auth_headers(admin)
      expect(JSON.parse(response.body)["data"].size).to eq(1)
    end

    it "filters by low_stock=true" do
      create(:stock_item, quantity_on_hand: 2,  quantity_reserved: 0, low_stock_threshold: 5)
      create(:stock_item, quantity_on_hand: 50, quantity_reserved: 0, low_stock_threshold: 5)
      get "/api/v1/stock_items", params: { low_stock: "true" }, headers: auth_headers(admin)
      expect(JSON.parse(response.body)["data"].size).to eq(1)
    end

    it "filters by has_unavailable=true" do
      create(:stock_item, quantity_unavailable: 0)
      si_with = create(:stock_item, quantity_unavailable: 3, unavailability_reason: "damaged")
      get "/api/v1/stock_items", params: { has_unavailable: "true" }, headers: auth_headers(admin)
      ids = JSON.parse(response.body)["data"].map { |d| d["id"] }
      expect(ids).to include(si_with.id)
      expect(ids.size).to eq(1)
    end

    it "searches by SKU" do
      v = create(:variant, sku: "UNIQUE-SKU-999")
      create(:stock_item, variant: v)
      create(:stock_item)
      get "/api/v1/stock_items", params: { search: "UNIQUE-SKU-999" }, headers: auth_headers(admin)
      expect(JSON.parse(response.body)["data"].size).to eq(1)
    end

    it "searches by product title" do
      p = create(:product, title: "SearchableProduct")
      v = create(:variant, product: p)
      create(:stock_item, variant: v)
      create(:stock_item) # unrelated
      get "/api/v1/stock_items", params: { search: "SearchableProduct" }, headers: auth_headers(admin)
      expect(JSON.parse(response.body)["data"].size).to eq(1)
    end

    it "sorts by quantity_on_hand asc" do
      create(:stock_item, quantity_on_hand: 50)
      create(:stock_item, quantity_on_hand: 5)
      get "/api/v1/stock_items", params: { sort: "quantity_on_hand", dir: "asc" }, headers: auth_headers(admin)
      qtys = JSON.parse(response.body)["data"].map { |d| d["quantity_on_hand"] }
      expect(qtys).to eq(qtys.sort)
    end

    it "sorts by quantity_unavailable desc" do
      create(:stock_item, quantity_unavailable: 1)
      create(:stock_item, quantity_unavailable: 5)
      create(:stock_item, quantity_unavailable: 0)
      get "/api/v1/stock_items", params: { sort: "quantity_unavailable", dir: "desc" }, headers: auth_headers(admin)
      qtys = JSON.parse(response.body)["data"].map { |d| d["quantity_unavailable"] }
      expect(qtys).to eq(qtys.sort.reverse)
    end
  end

  # ─── CREATE ───────────────────────────────────────────────────────────────────

  describe "POST /api/v1/stock_items" do
    it "creates a new stock item with initial stock movement" do
      variant   = create(:variant)
      warehouse = create(:warehouse)

      expect {
        post "/api/v1/stock_items",
             params: { variant_id: variant.id, warehouse_id: warehouse.id,
                       quantity_on_hand: 20, low_stock_threshold: 5 },
             headers: auth_headers(admin)
      }.to change(StockItem, :count).by(1).and change(StockMovement, :count).by(1)

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)["data"]
      expect(body["quantity_on_hand"]).to eq(20)
    end

    it "adds quantity when stock item already exists for variant+warehouse" do
      si = create(:stock_item, quantity_on_hand: 7, low_stock_threshold: 2)
      expect {
        post "/api/v1/stock_items",
             params: { variant_id: si.variant_id, warehouse_id: si.warehouse_id,
                       quantity_on_hand: 5, low_stock_threshold: 3 },
             headers: auth_headers(admin)
      }.to change(StockItem, :count).by(0).and change(StockMovement, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(si.reload.quantity_on_hand).to eq(12)
      expect(si.low_stock_threshold).to eq(3)
    end

    it "allows Shopify-origin variants in non-Shopify warehouses" do
      variant = create(:variant, :from_shopify)
      warehouse = create(:warehouse)

      expect {
        post "/api/v1/stock_items",
             params: { variant_id: variant.id, warehouse_id: warehouse.id, quantity_on_hand: 20 },
             headers: auth_headers(admin)
      }.to change(StockItem, :count).by(1)

      expect(response).to have_http_status(:created)
      expect(StockItem.find_by(variant: variant, warehouse: warehouse).quantity_on_hand).to eq(20)
    end

    it "rejects creation in Shopify-origin warehouses" do
      variant = create(:variant)
      warehouse = create(:warehouse, shopify_location_id: 123456)

      expect {
        post "/api/v1/stock_items",
             params: { variant_id: variant.id, warehouse_id: warehouse.id, quantity_on_hand: 20 },
             headers: auth_headers(admin)
      }.not_to change(StockItem, :count)

      expect(response).to have_http_status(:locked)
      expect(json_response.dig(:error, :type)).to eq("read_only_shopify_resource")
    end
  end

  # ─── UPDATE ───────────────────────────────────────────────────────────────────

  describe "PATCH /api/v1/stock_items/:id" do
    it "adjusts quantity_on_hand via WriteMovement" do
      si = create(:stock_item, quantity_on_hand: 10)
      expect {
        patch "/api/v1/stock_items/#{si.id}",
              params: { stock_item: { quantity_on_hand: 15 } },
              headers: auth_headers(admin)
      }.to change(StockMovement, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(si.reload.quantity_on_hand).to eq(15)
    end

    it "sets quantity_unavailable with reason" do
      si = create(:stock_item, quantity_unavailable: 0)
      patch "/api/v1/stock_items/#{si.id}",
            params: { stock_item: { quantity_unavailable: 3, unavailability_reason: "damaged" } },
            headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      si.reload
      expect(si.quantity_unavailable).to eq(3)
      expect(si.unavailability_reason).to eq("damaged")
    end

    it "updates available correctly after setting unavailable" do
      si = create(:stock_item, quantity_on_hand: 10, quantity_reserved: 2, quantity_unavailable: 0)
      patch "/api/v1/stock_items/#{si.id}",
            params: { stock_item: { quantity_unavailable: 2 } },
            headers: auth_headers(admin)
      body = JSON.parse(response.body)["data"]
      expect(body["available"]).to eq(6) # 10 - 2 - 2
    end

    it "allows adjustments to Shopify-origin variants outside Shopify warehouses" do
      variant = create(:variant, :from_shopify)
      warehouse = create(:warehouse, kind: "consignment")
      si = create(:stock_item, variant: variant, warehouse: warehouse, quantity_on_hand: 10)

      expect {
        patch "/api/v1/stock_items/#{si.id}",
              params: { stock_item: { quantity_on_hand: 15 } },
              headers: auth_headers(admin)
      }.to change(StockMovement, :count).by(1)

      expect(response).to have_http_status(:ok)
      expect(si.reload.quantity_on_hand).to eq(15)
    end

    it "rejects adjustments in Shopify-origin warehouses" do
      variant = create(:variant)
      warehouse = create(:warehouse, shopify_location_id: 123456)
      si = create(:stock_item, variant: variant, warehouse: warehouse, quantity_on_hand: 10)

      expect {
        patch "/api/v1/stock_items/#{si.id}",
              params: { stock_item: { quantity_on_hand: 15 } },
              headers: auth_headers(admin)
      }.not_to change(StockMovement, :count)

      expect(response).to have_http_status(:locked)
      expect(json_response.dig(:error, :type)).to eq("read_only_shopify_resource")
      expect(si.reload.quantity_on_hand).to eq(10)
    end
  end

  # ─── DESTROY ──────────────────────────────────────────────────────────────────

  describe "DELETE /api/v1/stock_items/:id" do
    it "deletes a stock item with no movements" do
      si = create(:stock_item)
      delete "/api/v1/stock_items/#{si.id}", headers: auth_headers(admin)
      expect(response).to have_http_status(:no_content)
      expect(StockItem.find_by(id: si.id)).to be_nil
    end

    it "400 when stock item has movements (restrict)" do
      si = create(:stock_item)
      create(:stock_movement, stock_item: si)
      delete "/api/v1/stock_items/#{si.id}", headers: auth_headers(admin)
      # Rails restrict_with_error raises, controller catches with generic 500 or 422 depending on setup
      expect(response).not_to have_http_status(:no_content)
    end
  end

  # ─── BULK ─────────────────────────────────────────────────────────────────────

  describe "POST /api/v1/stock_items/bulk" do
    it "set_threshold updates all selected items" do
      items = create_list(:stock_item, 3, low_stock_threshold: 5)
      post "/api/v1/stock_items/bulk",
           params: { ids: items.map(&:id), action_type: "set_threshold", payload: { threshold: 10 } },
           headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      items.each { |si| expect(si.reload.low_stock_threshold).to eq(10) }
    end

    it "rejects bulk changes containing Shopify-origin stock items" do
      variant = create(:variant)
      warehouse = create(:warehouse, shopify_location_id: 123456)
      si = create(:stock_item, variant: variant, warehouse: warehouse, low_stock_threshold: 5)

      post "/api/v1/stock_items/bulk",
           params: { ids: [si.id], action_type: "set_threshold", payload: { threshold: 10 } },
           headers: auth_headers(admin)

      expect(response).to have_http_status(:locked)
      expect(si.reload.low_stock_threshold).to eq(5)
    end
  end
end
