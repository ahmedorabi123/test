require "rails_helper"

RSpec.describe Catalog::Shopify::ProductUpserter do
  let(:webhook_payload) do
    {
      "id" => 4_567_890,
      "title" => "Classic Tee",
      "handle" => "classic-tee",
      "status" => "active",
      "vendor" => "ACME",
      "product_type" => "Apparel",
      "body_html" => "<p>A comfy tee.</p>",
      "updated_at" => "2026-04-20T10:00:00Z",
      "variants" => [
        {
          "id" => 99_001,
          "sku" => "TEE-S",
          "title" => "Small",
          "price" => "19.99",
          "compare_at_price" => "25.00",
          "barcode" => "0000001",
          "position" => 1,
          "inventory_item_id" => 555_001
        },
        {
          "id" => 99_002,
          "sku" => "TEE-M",
          "title" => "Medium",
          "price" => "19.99",
          "position" => 2,
          "inventory_item_id" => 555_002
        }
      ]
    }
  end

  it "creates a Product with its variants on first sync" do
    expect {
      described_class.call(webhook_payload)
    }.to change(Product, :count).by(1).and change(Variant, :count).by(2)

    product = Product.find_by(shopify_product_id: 4_567_890)
    expect(product.title).to eq("Classic Tee")
    expect(product.handle).to eq("classic-tee")
    expect(product.status).to eq("active")
    expect(product.vendor).to eq("ACME")
    expect(product.variants.map(&:sku)).to match_array(%w[TEE-S TEE-M])
    expect(product.variants.first.shopify_inventory_item_id).to eq(555_001)
  end

  it "is idempotent — updates instead of duplicating" do
    described_class.call(webhook_payload)
    webhook_payload["title"] = "Classic Tee (Renamed)"
    expect {
      described_class.call(webhook_payload)
    }.not_to change(Product, :count)

    expect(Product.first.title).to eq("Classic Tee (Renamed)")
  end

  it "prunes variants removed from Shopify" do
    described_class.call(webhook_payload)
    webhook_payload["variants"].pop # remove TEE-M
    expect {
      described_class.call(webhook_payload)
    }.to change(Variant, :count).by(-1)

    expect(Product.first.variants.pluck(:sku)).to eq(%w[TEE-S])
  end

  it "handles missing fields gracefully" do
    minimal = { "id" => 1_234, "title" => "Bare", "variants" => [] }
    product = described_class.call(minimal)
    expect(product).to be_persisted
    expect(product.handle).to eq("bare")
    expect(product.status).to eq("active")
  end
end
