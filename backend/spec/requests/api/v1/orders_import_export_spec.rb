require "rails_helper"

RSpec.describe "Api::V1::Orders import/export", type: :request do
  let(:admin) { create(:user, :admin) }

  describe "GET /api/v1/orders/export" do
    it "returns CSV bytes" do
      create(:order, order_number: "ORD-1001", customer_email: "x@example.com")
      get "/api/v1/orders/export", params: { format: "csv" }, headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("ORD-1001")
    end
  end

  describe "POST /api/v1/orders/import (preview)" do
    it "validates rows" do
      csv = <<~CSV
        Name,Currency,Total,Created at,Email,Financial Status
        #1001,USD,42.50,2025-01-01,buyer@example.com,paid
      CSV
      file = Rack::Test::UploadedFile.new(StringIO.new(csv), "text/csv", original_filename: "o.csv")
      post "/api/v1/orders/import", params: { file: file }, headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["data"]["total"]).to eq(1)
    end
  end

  describe "POST /api/v1/orders/import/commit" do
    it "creates orders via ManualOrderCreator" do
      csv = <<~CSV
        Name,Currency,Total,Created at,Email,Financial Status,Lineitem name,Lineitem quantity,Lineitem price
        #2001,USD,19.99,2025-01-01,buyer@example.com,pending,Test Item,1,19.99
      CSV
      file = Rack::Test::UploadedFile.new(StringIO.new(csv), "text/csv", original_filename: "o.csv")
      expect {
        post "/api/v1/orders/import/commit", params: { file: file }, headers: auth_headers(admin)
      }.to change { Order.count }.by(1)
      expect(JSON.parse(response.body)["data"]["created"]).to eq(1)
    end
  end

  describe "POST /api/v1/orders/import/commit?mode=showroom" do
    let!(:warehouse) { create(:warehouse, code: "SHOW-01") }
    let(:product)    { create(:product, title: "Tee") }
    let!(:variant)   { create(:variant, product: product, sku: "TEE-RED-M", price: "12.50") }
    let!(:stock_item) do
      create(:stock_item, variant: variant, warehouse: warehouse, quantity_on_hand: 20)
    end
    let!(:revenue_account)  { create(:account, code: "4000", name: "Sales Revenue",     account_type: "revenue",   normal_side: "credit") }
    let!(:tax_account)      { create(:account, code: "2200", name: "Sales Tax Payable", account_type: "liability", normal_side: "credit") }
    let!(:shipping_account) { create(:account, code: "4100", name: "Shipping Revenue",  account_type: "revenue",   normal_side: "credit") }
    let!(:ar_account)       { create(:account, code: "1100", name: "Accounts Receivable", account_type: "asset",  normal_side: "debit") }

    it "imports showroom CSV through ManualOrderCreator with reservations and accounting" do
      csv = <<~CSV
        Order #,SKU,Quantity,Price,Customer Email,Customer Name,Warehouse Code
        SHOW-1,TEE-RED-M,2,12.50,walkin@example.com,Walk In,SHOW-01
      CSV
      file = Rack::Test::UploadedFile.new(StringIO.new(csv), "text/csv", original_filename: "showroom.csv")

      expect {
        post "/api/v1/orders/import/commit",
             params: { file: file, mode: "showroom" },
             headers: auth_headers(admin)
      }.to change { Order.count }.by(1)

      order = Order.order(:created_at).last
      expect(order.source).to eq("showroom")
      expect(order.financial_status).to eq("paid")
      # Reservation created via Inventory::SyncOrderReservations
      expect(order.line_items.first.stock_reservations.where(status: "active").sum(:quantity)).to eq(2)
      # Sale journal posted (mark_paid path)
      expect(JournalEntry.where(idempotency_key: "sale-journal-#{order.id}")).to exist
    end
  end
end
