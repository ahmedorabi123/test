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

  # Note: the `?mode=showroom` import path was removed; manual showroom orders
  # now go through ManualOrderPage / `POST /api/v1/orders`.
end
