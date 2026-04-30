require "rails_helper"

RSpec.describe "Api::V1::Products import/export", type: :request do
  let(:admin) { create(:user, :admin) }

  describe "GET /api/v1/products/export" do
    it "returns CSV bytes with the product columns" do
      create(:product, title: "Tee", handle: "tee", status: "active", vendor: "Acme")
      get "/api/v1/products/export", params: { format: "csv" }, headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Type"]).to include("text/csv")
      expect(response.body).to include("Handle,Title,Status")
      expect(response.body).to include("tee")
    end

    it "supports xlsx" do
      create(:product)
      get "/api/v1/products/export", params: { format: "xlsx" }, headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(response.headers["Content-Type"]).to include("spreadsheetml")
    end
  end

  describe "POST /api/v1/products/import (preview)" do
    it "returns row counts and errors" do
      csv = <<~CSV
        Handle,Title,Status,Vendor,Variant SKU,Variant Price
        tee,Tee,active,Acme,TEE-001,19.99
        ,No Handle,active,Acme,X,1.00
      CSV
      file = Rack::Test::UploadedFile.new(StringIO.new(csv), "text/csv", original_filename: "p.csv")
      post "/api/v1/products/import", params: { file: file }, headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["data"]
      expect(data["total"]).to eq(2)
      expect(data["errors"].size).to be >= 1
    end
  end

  describe "POST /api/v1/products/import/commit" do
    it "creates products from CSV" do
      csv = <<~CSV
        Handle,Title,Status,Vendor,Variant SKU,Variant Price
        new-tee,New Tee,active,Acme,NTEE-001,19.99
      CSV
      file = Rack::Test::UploadedFile.new(StringIO.new(csv), "text/csv", original_filename: "p.csv")
      expect {
        post "/api/v1/products/import/commit", params: { file: file }, headers: auth_headers(admin)
      }.to change { Product.count }.by(1)
      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["data"]
      expect(data["created"]).to eq(1)
    end
  end

  describe "POST /api/v1/products/bulk" do
    it "archives products" do
      ids = create_list(:product, 2, status: "active").map(&:id)
      post "/api/v1/products/bulk", params: { ids: ids, action_type: "archive" }, headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(Product.where(id: ids).pluck(:status).uniq).to eq(["archived"])
    end
  end
end
