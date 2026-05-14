require "rails_helper"

RSpec.describe "Variants API", type: :request do
  let(:admin) { create(:user, :admin) }

  it "searches by variant and product fields without relation compatibility errors" do
    product = create(:product, title: "Origins Tee", handle: "origins-tee")
    variant = create(:variant, product: product, sku: "ORIG-BLK-M", title: "Black / M")

    get "/api/v1/variants", params: { search: "origins", per_page: 15 }, headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    expect(json.fetch("data").map { |row| row.fetch("id") }).to include(variant.id)
  end

  it "filters by warehouse availability when in_stock=true" do
    warehouse = create(:warehouse)
    product = create(:product, title: "Stock Tee")
    in_stock = create(:variant, product: product, sku: "STOCK-IN", title: "In")
    out_of_stock = create(:variant, product: product, sku: "STOCK-OUT", title: "Out")
    create(:stock_item, variant: in_stock, warehouse: warehouse, quantity_on_hand: 3)
    create(:stock_item, variant: out_of_stock, warehouse: warehouse, quantity_on_hand: 0)

    get "/api/v1/variants",
        params: { search: "stock", warehouse_id: warehouse.id, in_stock: "true" },
        headers: auth_headers(admin)

    expect(response).to have_http_status(:ok)
    ids = json.fetch("data").map { |row| row.fetch("id") }
    expect(ids).to include(in_stock.id)
    expect(ids).not_to include(out_of_stock.id)
  end

  it "clamps available stock at zero when reservations exceed on-hand" do
    warehouse = create(:warehouse)
    product = create(:product, title: "Clamp Tee")
    variant = create(:variant, product: product, sku: "CLAMP-1", title: "x")
    create(:stock_item,
      variant: variant, warehouse: warehouse,
      quantity_on_hand: 2, quantity_reserved: 5, quantity_unavailable: 0
    )

    get "/api/v1/variants",
        params: { search: "clamp", warehouse_id: warehouse.id, in_stock: "true" },
        headers: auth_headers(admin)

    ids = json.fetch("data").map { |row| row.fetch("id") }
    expect(ids).not_to include(variant.id)
  end

  it "rejects Shopify-origin warehouses with 422" do
    warehouse = create(:warehouse, shopify_location_id: "gid://shopify/Location/123")

    get "/api/v1/variants",
        params: { search: "x", warehouse_id: warehouse.id, in_stock: "true" },
        headers: auth_headers(admin)

    expect(response).to have_http_status(:unprocessable_entity)
  end

  it "returns 404 when warehouse_id does not exist" do
    get "/api/v1/variants",
        params: { search: "x", warehouse_id: SecureRandom.uuid, in_stock: "true" },
        headers: auth_headers(admin)

    expect(response).to have_http_status(:not_found)
  end

  def json
    JSON.parse(response.body)
  end
end
