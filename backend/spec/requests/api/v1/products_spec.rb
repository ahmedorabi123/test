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

    it "creates nested product options and values" do
      payload = {
        product: {
          title: "Option Tee",
          status: "active",
          product_options_attributes: [
            { name: "Size", position: 1, product_option_values_attributes: [
              { value: "Small", position: 1 },
              { value: "Medium", position: 2 }
            ] }
          ]
        }
      }

      expect {
        post "/api/v1/products", params: payload, as: :json, headers: auth_headers(admin)
      }.to change(ProductOption, :count).by(1).and change(ProductOptionValue, :count).by(2)

      expect(response).to have_http_status(:created)
    end
  end

  describe "POST /api/v1/products/:id/images" do
    it "uploads local product images through ActiveStorage" do
      product = create(:product)
      file = Tempfile.new(["product", ".png"])
      file.binmode
      file.write("png")
      file.rewind

      post "/api/v1/products/#{product.id}/images",
           params: { files: [Rack::Test::UploadedFile.new(file.path, "image/png", original_filename: "product.png")] },
           headers: auth_headers(admin)

      expect(response).to have_http_status(:created), response.body
      expect(JSON.parse(response.body).dig("data", 0, "filename")).to eq("product.png"), response.body
      attachment_count = ActiveStorage::Attachment.where(
        record_type: "Product",
        record_id: product.id,
        name: "uploaded_images"
      ).count
      expect(attachment_count).to eq(1), "attachments=#{attachment_count}, blobs=#{ActiveStorage::Blob.count}, body=#{response.body}"
    ensure
      file&.close!
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

  describe "GET /api/v1/products with collection_id filter" do
    it "returns only products in the given collection" do
      collection = create(:collection)
      p1 = create(:product)
      p2 = create(:product)
      collection.products << p1
      get "/api/v1/products", params: { collection_id: collection.id }, headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      ids = JSON.parse(response.body)["data"].map { |d| d["id"] }
      expect(ids).to include(p1.id)
      expect(ids).not_to include(p2.id)
    end
  end

  describe "product serializer inventory fields" do
    it "includes inventory_total and variants_count" do
      product = create(:product, :with_variant)
      get "/api/v1/products/#{product.id}", headers: auth_headers(admin)
      body = JSON.parse(response.body)["data"]
      expect(body).to have_key("inventory_total")
      expect(body).to have_key("variants_count")
    end
  end

  describe "DELETE /api/v1/products/:id soft-archive when referenced" do
    it "archives instead of deleting when variant is referenced by an order line item" do
      product = create(:product, :with_variant)
      variant = product.variants.first
      order   = create(:order)
      order.line_items.create!(
        variant: variant,
        title:    product.title,
        quantity: 1,
        price:    "10.00"
      )

      delete "/api/v1/products/#{product.id}", headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["meta"]["archived"]).to be true
      expect(product.reload.status).to eq("archived")
    end

    it "hard-deletes when no references exist" do
      product = create(:product, :with_variant)
      delete "/api/v1/products/#{product.id}", headers: auth_headers(admin)
      expect(response).to have_http_status(:no_content)
      expect(Product.find_by(id: product.id)).to be_nil
    end
  end
end
