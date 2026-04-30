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

  it "shows a single customer with recent orders" do
    c = create(:customer)
    create(:order, customer: c)
    get "/api/v1/customers/#{c.id}", headers: auth_headers(admin)
    expect(response).to have_http_status(:ok)
    expect(json_response[:data][:orders].size).to eq(1)
  end
end
