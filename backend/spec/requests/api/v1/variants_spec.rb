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

  def json
    JSON.parse(response.body)
  end
end
