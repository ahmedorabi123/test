require "rails_helper"

RSpec.describe "Api::V1::Orders sort", type: :request do
  let(:admin) { create(:user, :admin) }

  describe "GET /api/v1/orders?sort=order_number" do
    it "sorts by placed_at chronologically (proxied), not lexicographically by order_number" do
      # Three orders whose lexicographic order_number does NOT match
      # their issuance/placed_at order. The "Order #" column maps to
      # placed_at in the backend (Shopify-equivalent semantic).
      first  = create(:order, order_number: "SO-202605-ZZZZ", placed_at: 3.days.ago)
      second = create(:order, order_number: "SO-202605-AAAA", placed_at: 2.days.ago)
      third  = create(:order, order_number: "SO-202605-MMMM", placed_at: 1.day.ago)

      get "/api/v1/orders",
          params: { sort: "order_number", dir: "asc", per_page: 50 },
          headers: auth_headers(admin)

      ids = json_response[:data].map { |o| o[:id] }
      expect(ids).to eq([ first.id, second.id, third.id ])

      get "/api/v1/orders",
          params: { sort: "order_number", dir: "desc", per_page: 50 },
          headers: auth_headers(admin)

      ids = json_response[:data].map { |o| o[:id] }
      expect(ids).to eq([ third.id, second.id, first.id ])
    end
  end

  describe "GET /api/v1/orders?sort=delivery_status" do
    it "sorts on the denormalised orders.last_delivery_status (no N+1 fulfillment join)" do
      a = create(:order, order_number: "SO-202605-A001", placed_at: 3.days.ago)
      b = create(:order, order_number: "SO-202605-A002", placed_at: 2.days.ago)
      c = create(:order, order_number: "SO-202605-A003", placed_at: 1.day.ago)
      a.update_columns(last_delivery_status: "delivered")
      b.update_columns(last_delivery_status: "in_transit")
      c.update_columns(last_delivery_status: "pending")

      get "/api/v1/orders",
          params: { sort: "delivery_status", dir: "asc", per_page: 50 },
          headers: auth_headers(admin)

      statuses = json_response[:data].map { |o| o[:delivery_status] }
      expect(statuses.compact).to eq(statuses.compact.sort)
    end
  end
end
