require "rails_helper"

RSpec.describe "Api::V1::Orders", type: :request do
  let(:admin) { create(:user, :admin) }

  describe "GET /api/v1/orders" do
    it "401 without auth" do
      get "/api/v1/orders"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns paginated orders for admin" do
      create_list(:order, 3)
      get "/api/v1/orders", headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      body = json_response
      expect(body[:data].size).to eq(3)
      expect(body[:meta]).to include(:page, :per_page, :total, :summary)
      expect(body[:meta][:total]).to eq(3)
    end

    it "filters by status" do
      create(:order, status: "pending")
      create(:order, :fulfilled)
      get "/api/v1/orders", params: { status: "fulfilled" }, headers: auth_headers(admin)
      expect(json_response[:data].size).to eq(1)
      expect(json_response[:data].first[:status]).to eq("fulfilled")
    end

    it "filters by financial_status" do
      create(:order, financial_status: "pending")
      create(:order, financial_status: "paid")
      get "/api/v1/orders", params: { financial_status: "paid" }, headers: auth_headers(admin)
      expect(json_response[:data].size).to eq(1)
    end

    it "searches by order_number / customer_email" do
      create(:order, order_number: "SO-FIND-ME-1", customer_email: "alpha@example.com")
      create(:order, order_number: "SO-OTHER-2",   customer_email: "beta@example.com")
      get "/api/v1/orders", params: { search: "find-me" }, headers: auth_headers(admin)
      expect(json_response[:data].size).to eq(1)

      get "/api/v1/orders", params: { search: "beta@" }, headers: auth_headers(admin)
      expect(json_response[:data].size).to eq(1)
    end

    it "filters by date range" do
      create(:order, placed_at: 40.days.ago)
      create(:order, placed_at: 2.days.ago)
      get "/api/v1/orders",
          params: { from: 10.days.ago.iso8601 },
          headers: auth_headers(admin)
      expect(json_response[:data].size).to eq(1)
    end

    it "excludes line_items from the list (summary shape)" do
      create(:order, :with_line_items)
      get "/api/v1/orders", headers: auth_headers(admin)
      expect(json_response[:data].first).not_to have_key(:line_items)
    end
  end

  describe "GET /api/v1/orders/:id" do
    it "returns order with line_items" do
      order = create(:order, :with_line_items)
      get "/api/v1/orders/#{order.id}", headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(json_response[:data][:id]).to eq(order.id)
      expect(json_response[:data][:line_items].size).to eq(2)
    end

    it "404 for unknown id" do
      get "/api/v1/orders/#{SecureRandom.uuid}", headers: auth_headers(admin)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /api/v1/orders/stats" do
    it "returns counts and revenue for the window" do
      create(:order, :fulfilled, placed_at: 5.days.ago,  total_price: 100)
      create(:order,             placed_at: 2.days.ago,  total_price: 50)
      create(:order, :cancelled, placed_at: 1.day.ago,   total_price: 75)
      create(:order,             placed_at: 40.days.ago, total_price: 1000) # out of window

      get "/api/v1/orders/stats", params: { window: 30 }, headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      data = json_response[:data]
      expect(data[:window_days]).to eq(30)
      expect(data[:count]).to eq(3)
      # cancelled excluded from revenue
      expect(data[:total_revenue].to_f).to eq(150.0)
      expect(data[:by_status]).to include(:fulfilled, :pending, :cancelled)
    end
  end

  describe "RBAC" do
    it "allows a viewer (read-only) to read orders" do
      # Ensure the orders:read permission exists in this spec's DB
      perm = Permission.find_or_create_by!(resource: "orders", action: "read")
      viewer_role = Role.find_or_create_by!(name: "viewer") { |r| r.description = "v" }
      viewer_role.permissions = [perm]
      viewer = create(:user)
      viewer.user_roles.create!(role: viewer_role)

      get "/api/v1/orders", headers: auth_headers(viewer)
      expect(response).to have_http_status(:ok)
    end

    it "403 for a user with no roles" do
      nobody = create(:user)
      get "/api/v1/orders", headers: auth_headers(nobody)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "GET /api/v1/orders pagination" do
    it "respects per_page and page params" do
      create_list(:order, 5)
      get "/api/v1/orders", params: { per_page: 2, page: 1 }, headers: auth_headers(admin)
      body = json_response
      expect(body[:data].size).to eq(2)
      expect(body[:meta][:total]).to eq(5)
    end
  end

  describe "GET /api/v1/orders stats edge cases" do
    it "returns zero counts and zero revenue when no orders in window" do
      get "/api/v1/orders/stats", params: { window: 7 }, headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      data = json_response[:data]
      expect(data[:count]).to eq(0)
      expect(data[:total_revenue].to_f).to eq(0.0)
    end

    it "defaults to 30-day window when window param absent" do
      create(:order, placed_at: 5.days.ago, total_price: 100, financial_status: "paid", status: "fulfilled")
      create(:order, placed_at: 40.days.ago, total_price: 999, financial_status: "paid", status: "fulfilled")
      get "/api/v1/orders/stats", headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(json_response[:data][:count]).to eq(1)
    end

    it "includes fulfilled orders in revenue but excludes cancelled" do
      create(:order, :fulfilled,  placed_at: 2.days.ago, total_price: 200)
      create(:order, :cancelled,  placed_at: 2.days.ago, total_price: 500)
      get "/api/v1/orders/stats", params: { window: 7 }, headers: auth_headers(admin)
      expect(json_response[:data][:total_revenue].to_f).to eq(200.0)
    end
  end

  describe "GET /api/v1/orders/:id — 401 without auth" do
    it "returns 401" do
      order = create(:order)
      get "/api/v1/orders/#{order.id}"
      expect(response).to have_http_status(:unauthorized)
    end
  end

  describe "warehouse filter" do
    it "filters by warehouse_id (Order#location_id)" do
      wh_a = create(:warehouse)
      wh_b = create(:warehouse)
      o1 = create(:order, location_id: wh_a.id)
      _o2 = create(:order, location_id: wh_b.id)

      get "/api/v1/orders", params: { warehouse_id: wh_a.id }, headers: auth_headers(admin)
      ids = json_response[:data].map { |r| r[:id] }
      expect(ids).to eq([ o1.id ])
    end
  end
end
