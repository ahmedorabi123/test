require "rails_helper"

RSpec.describe "Api::V1::Collections", type: :request do
  let(:admin) { create(:user, :admin) }

  # ─── INDEX ────────────────────────────────────────────────────────────────────

  describe "GET /api/v1/collections" do
    it "401 without auth" do
      get "/api/v1/collections"
      expect(response).to have_http_status(:unauthorized)
    end

    it "returns paginated collections" do
      create_list(:collection, 3)
      get "/api/v1/collections", headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["data"].size).to eq(3)
      expect(body["meta"]).to include("page", "per_page", "total")
    end

    it "filters by kind=custom" do
      create(:collection, kind: "custom")
      create(:collection, :smart)
      get "/api/v1/collections", params: { kind: "custom" }, headers: auth_headers(admin)
      expect(JSON.parse(response.body)["data"].size).to eq(1)
    end

    it "filters by kind=smart" do
      create(:collection, kind: "custom")
      create(:collection, :smart)
      get "/api/v1/collections", params: { kind: "smart" }, headers: auth_headers(admin)
      expect(JSON.parse(response.body)["data"].size).to eq(1)
    end

    it "searches by title" do
      create(:collection, title: "Summer Sale")
      create(:collection, title: "Winter Basics")
      get "/api/v1/collections", params: { search: "summer" }, headers: auth_headers(admin)
      expect(JSON.parse(response.body)["data"].size).to eq(1)
    end
  end

  # ─── SHOW ─────────────────────────────────────────────────────────────────────

  describe "GET /api/v1/collections/:id" do
    it "returns collection with products_count" do
      collection = create(:collection)
      get "/api/v1/collections/#{collection.id}", headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body["data"]["id"]).to eq(collection.id)
      expect(body["data"]).to have_key("products_count")
    end

    it "404 for unknown id" do
      get "/api/v1/collections/#{SecureRandom.uuid}", headers: auth_headers(admin)
      expect(response).to have_http_status(:not_found)
    end
  end

  # ─── CREATE ───────────────────────────────────────────────────────────────────

  describe "POST /api/v1/collections" do
    it "creates a custom collection" do
      post "/api/v1/collections",
           params: { collection: { title: "New Arrivals" } },
           headers: auth_headers(admin)
      expect(response).to have_http_status(:created)
      body = JSON.parse(response.body)
      expect(body["data"]["title"]).to eq("New Arrivals")
      expect(body["data"]["kind"]).to eq("custom")
    end

    it "derives handle from title" do
      post "/api/v1/collections",
           params: { collection: { title: "My Collection" } },
           headers: auth_headers(admin)
      expect(JSON.parse(response.body)["data"]["handle"]).to eq("my-collection")
    end

    it "422 when creating a smart collection directly" do
      post "/api/v1/collections",
           params: { collection: { title: "Smart", kind: "smart" } },
           headers: auth_headers(admin)
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it "422 without required fields" do
      post "/api/v1/collections",
           params: { collection: { kind: "custom" } },
           headers: auth_headers(admin)
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  # ─── UPDATE ───────────────────────────────────────────────────────────────────

  describe "PATCH /api/v1/collections/:id" do
    it "updates a custom collection" do
      collection = create(:collection)
      patch "/api/v1/collections/#{collection.id}",
            params: { collection: { title: "Updated Title" } },
            headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)["data"]["title"]).to eq("Updated Title")
    end

    it "returns 403 when trying to update rules on a smart collection" do
      smart = create(:collection, :smart)
      patch "/api/v1/collections/#{smart.id}",
            params: { collection: { title: "Renamed Smart", rules: [{ "column" => "vendor" }] } },
            headers: auth_headers(admin)
      expect(response).to have_http_status(:forbidden)
    end

    it "allows updating non-rules fields on a smart collection" do
      smart = create(:collection, :smart)
      patch "/api/v1/collections/#{smart.id}",
            params: { collection: { title: "Renamed Smart" } },
            headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(smart.reload.title).to eq("Renamed Smart")
    end

    it "rejects updates to Shopify-origin collections" do
      collection = create(:collection, :from_shopify, title: "Shopify Collection")
      patch "/api/v1/collections/#{collection.id}",
            params: { collection: { title: "ERP Edit" } },
            headers: auth_headers(admin)

      expect(response).to have_http_status(:forbidden)
      expect(json_response.dig(:error, :type)).to eq("read_only_shopify_resource")
      expect(collection.reload.title).to eq("Shopify Collection")
    end
  end

  # ─── DESTROY ──────────────────────────────────────────────────────────────────

  describe "DELETE /api/v1/collections/:id" do
    it "deletes a custom collection" do
      collection = create(:collection)
      delete "/api/v1/collections/#{collection.id}", headers: auth_headers(admin)
      expect(response).to have_http_status(:no_content)
      expect(Collection.find_by(id: collection.id)).to be_nil
    end

    it "403 when deleting a smart collection" do
      smart = create(:collection, :smart)
      delete "/api/v1/collections/#{smart.id}", headers: auth_headers(admin)
      expect(response).to have_http_status(:forbidden)
      expect(Collection.find_by(id: smart.id)).not_to be_nil
    end
  end

  # ─── ADD / REMOVE PRODUCT ────────────────────────────────────────────────────

  describe "POST /api/v1/collections/:id/products" do
    it "adds a product to a collection" do
      collection = create(:collection)
      product    = create(:product)
      post "/api/v1/collections/#{collection.id}/products",
           params: { product_id: product.id },
           headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(collection.products.reload).to include(product)
    end

    it "is idempotent — adding the same product twice does not error" do
      collection = create(:collection)
      product    = create(:product)
      2.times do
        post "/api/v1/collections/#{collection.id}/products",
             params: { product_id: product.id },
             headers: auth_headers(admin)
      end
      expect(response).to have_http_status(:ok)
      expect(collection.collection_products.reload.count).to eq(1)
    end
  end

  describe "DELETE /api/v1/collections/:id/products/:product_id" do
    it "removes a product from a collection" do
      collection = create(:collection)
      product    = create(:product)
      collection.products << product
      delete "/api/v1/collections/#{collection.id}/products/#{product.id}",
             headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
      expect(collection.products.reload).not_to include(product)
    end

    it "succeeds silently when product is not in collection" do
      collection = create(:collection)
      product    = create(:product)
      delete "/api/v1/collections/#{collection.id}/products/#{product.id}",
             headers: auth_headers(admin)
      expect(response).to have_http_status(:ok)
    end

    it "rejects membership edits on Shopify-origin collections" do
      collection = create(:collection, :from_shopify)
      product = create(:product)

      post "/api/v1/collections/#{collection.id}/products",
           params: { product_id: product.id },
           headers: auth_headers(admin)

      expect(response).to have_http_status(:forbidden)
      expect(collection.products.reload).to be_empty
    end
  end
end
