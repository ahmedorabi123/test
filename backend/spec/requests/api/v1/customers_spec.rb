require "rails_helper"

RSpec.describe "Api::V1::Customers", type: :request do
  let(:admin) { create(:user, :admin) }

  it "401 without auth" do
    get "/api/v1/customers"
    expect(response).to have_http_status(:unauthorized)
  end

  it "lists customers for admin" do
    create(:customer, email: "a@x.com", first_name: "Ada")
    create(:customer, email: "b@x.com", first_name: "Bob")
    get "/api/v1/customers", headers: auth_headers(admin)
    expect(response).to have_http_status(:ok)
    expect(json_response[:data].size).to eq(2)
    expect(json_response[:data].first).to include(:display_name, :orders_count, :total_spent)
  end

  it "searches by email / name" do
    create(:customer, email: "alpha@example.com", first_name: "Alpha")
    create(:customer, email: "other@example.com", first_name: "Other")
    get "/api/v1/customers", params: { search: "alpha" }, headers: auth_headers(admin)
    expect(json_response[:data].size).to eq(1)
  end

  it "searches by full name" do
    match = create(:customer, email: "full@example.com", first_name: "Nour", last_name: "Hassan")
    create(:customer, email: "other@example.com", first_name: "Nour", last_name: "Else")

    get "/api/v1/customers", params: { search: "Nour Hassan" }, headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    expect(json_response[:data].map { |row| row[:id] }).to eq([match.id])
  end

  it "shows a single customer with recent orders" do
    c = create(:customer)
    create(:order, customer: c)
    get "/api/v1/customers/#{c.id}", headers: auth_headers(admin)
    expect(response).to have_http_status(:ok)
    expect(json_response[:data][:orders].size).to eq(1)
  end

  describe "sorting" do
    it "sorts by orders_count desc and asc" do
      a = create(:customer, email: "a@x.com", orders_count: 1)
      b = create(:customer, email: "b@x.com", orders_count: 5)
      c = create(:customer, email: "c@x.com", orders_count: 3)

      get "/api/v1/customers", params: { sort: "orders_count", dir: "desc" }, headers: auth_headers(admin)
      expect(json_response[:data].map { |r| r[:id] }).to eq([b.id, c.id, a.id])

      get "/api/v1/customers", params: { sort: "orders_count", dir: "asc" }, headers: auth_headers(admin)
      expect(json_response[:data].map { |r| r[:id] }).to eq([a.id, c.id, b.id])
    end

    it "sorts by total_spent" do
      lo = create(:customer, email: "lo@x.com", total_spent: 10)
      hi = create(:customer, email: "hi@x.com", total_spent: 999)
      get "/api/v1/customers", params: { sort: "total_spent", dir: "desc" }, headers: auth_headers(admin)
      expect(json_response[:data].first[:id]).to eq(hi.id)
      expect(json_response[:data].last[:id]).to eq(lo.id)
    end

    it "sorts by last_order_at with NULLS LAST" do
      with_order  = create(:customer, email: "w@x.com", last_order_at: 1.day.ago)
      no_order    = create(:customer, email: "n@x.com", last_order_at: nil)
      older_order = create(:customer, email: "o@x.com", last_order_at: 10.days.ago)

      get "/api/v1/customers", params: { sort: "last_order_at", dir: "desc" }, headers: auth_headers(admin)
      ids = json_response[:data].map { |r| r[:id] }
      expect(ids.first).to eq(with_order.id)
      expect(ids.last).to eq(no_order.id)
      expect(ids).to include(older_order.id)
    end

    it "sorts by source" do
      manual = create(:customer, email: "manual@x.com", source: "manual")
      shopify = create(:customer, email: "shopify@x.com", source: "shopify")

      get "/api/v1/customers", params: { sort: "source", dir: "desc" }, headers: auth_headers(admin)

      expect(json_response[:data].map { |r| r[:id] }).to eq([shopify.id, manual.id])
    end
  end

  describe "show with last_order" do
    it "embeds last_order with line items" do
      c = create(:customer)
      _old = create(:order, customer: c, placed_at: 5.days.ago)
      newest = create(:order, :with_line_items, customer: c, placed_at: 1.hour.ago)
      get "/api/v1/customers/#{c.id}", headers: auth_headers(admin)
      lo = json_response[:data][:last_order]
      expect(lo).to be_present
      expect(lo[:id]).to eq(newest.id)
      expect(lo[:line_items].size).to eq(2)
    end

    it "last_order is nil when customer has no orders" do
      c = create(:customer)
      get "/api/v1/customers/#{c.id}", headers: auth_headers(admin)
      expect(json_response[:data][:last_order]).to be_nil
    end
  end

  describe "create validations" do
    it "rejects when both email and phone are blank" do
      post "/api/v1/customers",
           params: { customer: { first_name: "No", last_name: "Contact" } },
           headers: auth_headers(admin)
      expect(response).to have_http_status(:unprocessable_entity)
      expect(response.body).to match(/Email or phone/i)
    end

    it "accepts email-only" do
      post "/api/v1/customers",
           params: { customer: { email: "only@x.com" } },
           headers: auth_headers(admin)
      expect(response).to have_http_status(:created)
    end

    it "accepts phone-only" do
      post "/api/v1/customers",
           params: { customer: { phone: "+15550000" } },
           headers: auth_headers(admin)
      expect(response).to have_http_status(:created)
    end

    it "rejects malformed email" do
      post "/api/v1/customers",
           params: { customer: { email: "not-an-email" } },
           headers: auth_headers(admin)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  describe "update permits Shopify fields" do
    it "persists accepts_marketing, tax_exempt, note, tags, default_address" do
      c = create(:customer)
      patch "/api/v1/customers/#{c.id}",
            params: {
              customer: {
                accepts_marketing: true,
                tax_exempt: true,
                note: "VIP",
                tags: %w[vip wholesale],
                default_address: { address1: "1 Main", city: "Cairo", country: "EG", zip: "11111" }
              }
            },
            headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      c.reload
      expect(c.accepts_marketing).to eq(true)
      expect(c.tax_exempt).to eq(true)
      expect(c.note).to eq("VIP")
      expect(c.tags).to match_array(%w[vip wholesale])
      expect(c.default_address["address1"]).to eq("1 Main")
    end

    it "rejects updates to Shopify-origin customers" do
      customer = create(:customer, source: "shopify", shopify_customer_id: 123456, first_name: "Shopify")

      patch "/api/v1/customers/#{customer.id}",
            params: { customer: { first_name: "ERP" } },
            headers: auth_headers(admin)

      expect(response).to have_http_status(:locked)
      expect(json_response.dig(:error, :type)).to eq("read_only_shopify_resource")
      expect(customer.reload.first_name).to eq("Shopify")
    end
  end

  describe "bulk actions" do
    it "adds and removes tags across multiple customers" do
      a = create(:customer, email: "a@x.com", tags: %w[old])
      b = create(:customer, email: "b@x.com", tags: [])

      post "/api/v1/customers/bulk",
           params: { ids: [a.id, b.id], action_type: "add_tag", payload: { tag: "vip" } },
           headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(a.reload.tags).to include("vip")
      expect(b.reload.tags).to eq(%w[vip])

      post "/api/v1/customers/bulk",
           params: { ids: [a.id, b.id], action_type: "remove_tag", payload: { tag: "vip" } },
           headers: auth_headers(admin)
      expect(a.reload.tags).not_to include("vip")
      expect(b.reload.tags).not_to include("vip")
    end

    it "deletes only customers without orders" do
      keep = create(:customer, email: "keep@x.com")
      create(:order, customer: keep)
      drop = create(:customer, email: "drop@x.com")

      post "/api/v1/customers/bulk",
           params: { ids: [keep.id, drop.id], action_type: "delete" },
           headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(Customer.exists?(keep.id)).to be true
      expect(Customer.exists?(drop.id)).to be false
    end

    it "rejects bulk mutations containing Shopify-origin customers" do
      customer = create(:customer, source: "shopify", shopify_customer_id: 123456)

      post "/api/v1/customers/bulk",
           params: { ids: [customer.id], action_type: "add_tag", payload: { tag: "vip" } },
           headers: auth_headers(admin)

      expect(response).to have_http_status(:locked)
      expect(customer.reload.tags).to be_empty
    end
  end
end
