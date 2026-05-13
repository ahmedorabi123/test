require "rails_helper"

RSpec.describe "Api::V1::StockTransfers", type: :request do
  let(:admin)   { create(:user, :admin) }
  let(:from_wh) { create(:warehouse, code: "WH-A") }
  let(:to_wh)   { create(:warehouse, code: "WH-B") }
  let(:product) { create(:product) }
  let(:v1)      { create(:variant, product: product, sku: "T1") }
  let(:v2)      { create(:variant, product: product, sku: "T2") }

  before do
    create(:stock_item, variant: v1, warehouse: from_wh, quantity_on_hand: 10)
    create(:stock_item, variant: v2, warehouse: from_wh, quantity_on_hand: 5)
  end

  describe "POST /api/v1/stock_transfers" do
    it "creates a multi-variant batch transfer" do
      post "/api/v1/stock_transfers",
           params: {
             stock_transfer: {
               from_warehouse_id: from_wh.id,
               to_warehouse_id:   to_wh.id,
               reason:            "restock"
             },
             lines: [
               { variant_id: v1.id, quantity: 3 },
               { variant_id: v2.id, quantity: 2 }
             ]
           }, as: :json, headers: auth_headers(admin)

      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)["data"]
      expect(body["lines"].size).to eq(2)
      expect(body["movements"].size).to eq(4)
      expect(body["reference"]).to match(/\ATR-\d{4}-\d{4}\z/)
      expect(StockMovement.count).to eq(4)
    end

    it "still accepts the legacy single-variant payload" do
      post "/api/v1/stock_transfers",
           params: {
             variant_id: v1.id,
             from_warehouse_id: from_wh.id,
             to_warehouse_id: to_wh.id,
             quantity: 2
           }, as: :json, headers: auth_headers(admin)

      expect(response).to have_http_status(:created), -> { response.body }
      expect(StockTransfer.count).to eq(1)
      expect(StockTransferLine.count).to eq(1)
    end

    it "returns 422 insufficient_stock when source has too little" do
      post "/api/v1/stock_transfers",
           params: {
             stock_transfer: { from_warehouse_id: from_wh.id, to_warehouse_id: to_wh.id, reason: "transfer" },
             lines: [{ variant_id: v1.id, quantity: 9_999 }]
           }, as: :json, headers: auth_headers(admin)

      expect(response).to have_http_status(:unprocessable_content)
      body = JSON.parse(response.body)
      expect(body.dig("error", "type")).to eq("insufficient_stock")
      expect(body.dig("error", "code", "variant_id")).to eq(v1.id)
      expect(StockTransfer.count).to eq(0)
    end

    it "returns 403 when transferring to/from a Shopify-origin warehouse" do
      shop_wh = create(:warehouse, code: "WH-SHOP", shopify_location_id: 12345)
      post "/api/v1/stock_transfers",
           params: {
             stock_transfer: { from_warehouse_id: from_wh.id, to_warehouse_id: shop_wh.id, reason: "transfer" },
             lines: [{ variant_id: v1.id, quantity: 1 }]
           }, as: :json, headers: auth_headers(admin)

      expect(response).to have_http_status(:forbidden)
      expect(JSON.parse(response.body).dig("error", "type")).to eq("read_only_shopify_resource")
    end

    it "returns 422 for duplicate variants in the payload" do
      post "/api/v1/stock_transfers",
           params: {
             stock_transfer: { from_warehouse_id: from_wh.id, to_warehouse_id: to_wh.id, reason: "transfer" },
             lines: [
               { variant_id: v1.id, quantity: 1 },
               { variant_id: v1.id, quantity: 1 }
             ]
           }, as: :json, headers: auth_headers(admin)
      expect(response).to have_http_status(:unprocessable_content)
      expect(JSON.parse(response.body).dig("error", "type")).to eq("validation")
    end

    it "writes an audit log entry" do
      expect {
        post "/api/v1/stock_transfers",
             params: {
               stock_transfer: { from_warehouse_id: from_wh.id, to_warehouse_id: to_wh.id, reason: "transfer" },
               lines: [{ variant_id: v1.id, quantity: 1 }]
             }, as: :json, headers: auth_headers(admin)
      }.to change { AuditLog.where(action: "inventory.transfer.posted").count }.by(1)
    end
  end

  describe "GET /api/v1/stock_transfers" do
    it "returns recent transfers paginated" do
      Inventory::PostStockTransfer.call(
        header_attrs: { from_warehouse_id: from_wh.id, to_warehouse_id: to_wh.id, reason: "transfer" },
        lines: [{ variant_id: v1.id, quantity: 1 }],
        actor: admin
      )
      get "/api/v1/stock_transfers", headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["data"].size).to eq(1)
      expect(body["meta"]["total"]).to eq(1)
    end

    it "filters by warehouse" do
      Inventory::PostStockTransfer.call(
        header_attrs: { from_warehouse_id: from_wh.id, to_warehouse_id: to_wh.id, reason: "transfer" },
        lines: [{ variant_id: v1.id, quantity: 1 }],
        actor: admin
      )
      other = create(:warehouse, code: "WH-C")
      get "/api/v1/stock_transfers",
          params: { from_warehouse_id: other.id }, headers: auth_headers(admin)
      expect(JSON.parse(response.body)["data"]).to be_empty
    end
  end

  describe "GET /api/v1/stock_transfers/:id" do
    it "returns header + lines + movements" do
      t = Inventory::PostStockTransfer.call(
        header_attrs: { from_warehouse_id: from_wh.id, to_warehouse_id: to_wh.id, reason: "transfer" },
        lines: [{ variant_id: v1.id, quantity: 2 }],
        actor: admin
      )
      get "/api/v1/stock_transfers/#{t.id}", headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)["data"]
      expect(body["lines"].size).to eq(1)
      expect(body["movements"].size).to eq(2)
    end
  end
end
