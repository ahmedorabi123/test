require "rails_helper"

RSpec.describe Variant, type: :model do
  it "belongs to a product" do
    variant = build(:variant, product: nil)
    expect(variant).not_to be_valid
    expect(variant.errors[:product]).to be_present
  end

  it "validates price is non-negative" do
    v = build(:variant, price: -1)
    expect(v).not_to be_valid
  end

  it "allows blank SKU but enforces uniqueness when present" do
    create(:variant, sku: "ABC")
    v = build(:variant, sku: "ABC")
    expect(v).not_to be_valid
    expect(v.errors[:sku]).to be_present

    blank = build(:variant, sku: nil)
    expect(blank).to be_valid
  end

  it "allows cost updates on Shopify-origin variants" do
    variant = create(:variant, shopify_variant_id: 123_456)

    expect(variant.update(cost: 12.34, cost_per_item: 12.34)).to be(true)
  end

  it "blocks non-cost updates on Shopify-origin variants" do
    variant = create(:variant, shopify_variant_id: 123_456)

    expect(variant.update(title: "Manual edit")).to be(false)
    expect(variant.errors[:base]).to include(Shopify::Origin::READ_ONLY_MESSAGE)
  end
end
