require "rails_helper"

RSpec.describe "Api::V1::Customers import/export", type: :request do
  let(:admin) { create(:user, :admin) }

  describe "GET /api/v1/customers/export" do
    it "returns CSV bytes" do
      create(:customer, email: "alice@example.com", first_name: "Alice")
      get "/api/v1/customers/export", params: { format: "csv" }, headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("alice@example.com")
    end
  end

  describe "POST /api/v1/customers/import" do
    it "previews and reports row counts" do
      csv = <<~CSV
        First Name,Last Name,Email,Phone,Tags
        Bob,Smith,bob@example.com,5550100,vip
        ,,bad-email,,
      CSV
      file = Rack::Test::UploadedFile.new(StringIO.new(csv), "text/csv", original_filename: "c.csv")
      post "/api/v1/customers/import", params: { file: file }, headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      data = JSON.parse(response.body)["data"]
      expect(data["total"]).to eq(2)
      expect(data["errors"].size).to be >= 1
    end
  end

  describe "POST /api/v1/customers/import/commit" do
    it "creates customers" do
      csv = <<~CSV
        First Name,Last Name,Email,Phone
        Carol,Doe,carol@example.com,5550111
      CSV
      file = Rack::Test::UploadedFile.new(StringIO.new(csv), "text/csv", original_filename: "c.csv")
      expect {
        post "/api/v1/customers/import/commit", params: { file: file }, headers: auth_headers(admin)
      }.to change { Customer.count }.by(1)
      expect(JSON.parse(response.body)["data"]["created"]).to eq(1)
    end
  end
end
