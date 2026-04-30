require "rails_helper"

RSpec.describe "Api::V1::Products", type: :request do
  let(:admin) { create(:user, :admin) }

  describe "GET /api/v1/products" do
    it "401 without auth" do
      get "/api/v1/products"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns paginated products for authenticated admin" do
      create_list(:product, 3)
      get "/api/v1/products", headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["data"].size).to eq(3)
      expect(body["meta"]).to include("page", "per_page", "total")
      expect(body["meta"]["total"]).to eq(3)
    end

    it "filters by search term on title or handle" do
      create(:product, title: "Blue Shirt",  handle: "blue-shirt")
      create(:product, title: "Green Hat",   handle: "green-hat")
      get "/api/v1/products", params: { search: "blue" }, headers: auth_headers(admin)
      expect(JSON.parse(response.body)["data"].size).to eq(1)
    end

    it "filters by status" do
      create(:product, status: "active")
      create(:product, status: "draft")
      get "/api/v1/products", params: { status: "draft" }, headers: auth_headers(admin)
      expect(JSON.parse(response.body)["data"].size).to eq(1)
    end
  end

  describe "GET /api/v1/products/:id" do
    it "returns product with variants" do
      product = create(:product, :with_variant)
      get "/api/v1/products/#{product.id}", headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["data"]["id"]).to eq(product.id)
      expect(body["data"]["variants"].size).to eq(1)
    end

    it "404 for unknown id" do
      get "/api/v1/products/#{SecureRandom.uuid}", headers: auth_headers(admin)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /api/v1/products" do
    it "creates a product with nested variants" do
      payload = {
        product: {
          title: "Beanie",
          status: "active",
          variants_attributes: [
            { title: "One Size", sku: "BEANIE-OS", price: "12.50" }
          ]
        }
      }
      expect {
        post "/api/v1/products", params: payload, as: :json, headers: auth_headers(admin)
      }.to change(Product, :count).by(1).and change(Variant, :count).by(1)

      expect(response).to have_http_status(:created)
    end

    it "422 on validation failure" do
      post "/api/v1/products", params: { product: { title: "" } }, as: :json, headers: auth_headers(admin)
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "PATCH /api/v1/products/:id" do
    it "updates title" do
      product = create(:product, title: "Old")
      patch "/api/v1/products/#{product.id}",
            params: { product: { title: "New" } },
            as: :json,
            headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(product.reload.title).to eq("New")
    end
  end

  describe "DELETE /api/v1/products/:id" do
    it "destroys the product" do
      product = create(:product)
      delete "/api/v1/products/#{product.id}", headers: auth_headers(admin)
      expect(response).to have_http_status(:no_content)
      expect(Product.where(id: product.id)).to be_empty
    end
  end

  describe "RBAC" do
    it "403 for a viewer trying to create" do
      viewer_role = Role.find_or_create_by!(name: "viewer") { |r| r.description = "v" }
      viewer_role.permissions = Permission.where(action: "read")
      viewer = create(:user)
      viewer.user_roles.create!(role: viewer_role)

      post "/api/v1/products", params: { product: { title: "X" } }, as: :json, headers: auth_headers(viewer)
      expect(response).to have_http_status(:forbidden)
    end
  end

  describe "pagination" do
    it "respects per_page param" do
      create_list(:product, 5)
      get "/api/v1/products", params: { per_page: 2, page: 1 }, headers: auth_headers(admin)
      body = JSON.parse(response.body)
      expect(body["data"].size).to eq(2)
      expect(body["meta"]["per_page"]).to eq(2)
      expect(body["meta"]["total"]).to eq(5)
    end

    it "returns page 2 correctly" do
      create_list(:product, 5)
      get "/api/v1/products", params: { per_page: 3, page: 2 }, headers: auth_headers(admin)
      body = JSON.parse(response.body)
      expect(body["data"].size).to eq(2)
    end
  end

  describe "POST /api/v1/products with multiple variants" do
    it "creates a product with two variants" do
      payload = {
        product: {
          title: "Multi Tee",
          status: "active",
          variants_attributes: [
            { title: "Small",  sku: "MTEE-S", price: "10.00" },
            { title: "Medium", sku: "MTEE-M", price: "11.00" }
          ]
        }
      }
      expect {
        post "/api/v1/products", params: payload, as: :json, headers: auth_headers(admin)
      }.to change(Product, :count).by(1).and change(Variant, :count).by(2)

      body = JSON.parse(response.body)
      expect(body["data"]["variants"].size).to eq(2)
    end
  end

  describe "PATCH /api/v1/products/:id nested variant update" do
    it "updates an existing variant via nested attributes" do
      product = create(:product, :with_variant)
      variant = product.variants.first

      patch "/api/v1/products/#{product.id}",
            params: {
              product: {
                variants_attributes: [{ id: variant.id, price: "99.99" }]
              }
            },
            as: :json,
            headers: auth_headers(admin)

      expect(response).to have_http_status(:ok)
      expect(variant.reload.price).to be_within(0.01).of(99.99)
    end
  end

  describe "GET /api/v1/products with shopify filter" do
    it "returns only Shopify-linked products when from_shopify=true" do
      create(:product, :from_shopify)
      create(:product)
      get "/api/v1/products", params: { from_shopify: "true" }, headers: auth_headers(admin)
      expect(JSON.parse(response.body)["data"].size).to eq(1)
    end
  end
end
