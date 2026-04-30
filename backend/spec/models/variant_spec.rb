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
end
