require "rails_helper"

RSpec.describe Product, type: :model do
  it "validates presence of title" do
    p = Product.new(handle: "x")
    expect(p).not_to be_valid
    expect(p.errors[:title]).to be_present
  end

  it "derives handle from title when blank" do
    p = Product.new(title: "Hello World!")
    p.valid?
    expect(p.handle).to eq("hello-world")
  end

  it "enforces status inclusion" do
    p = build(:product, status: "weird")
    expect(p).not_to be_valid
    expect(p.errors[:status]).to be_present
  end

  it "enforces handle uniqueness case-insensitively" do
    create(:product, handle: "blue-tee")
    p = build(:product, handle: "Blue-Tee")
    expect(p).not_to be_valid
  end

  describe "scopes" do
    it "active filters by status" do
      create(:product, status: "active")
      create(:product, status: "draft")
      expect(Product.active.count).to eq(1)
    end

    it "from_shopify filters linked records" do
      create(:product, :from_shopify)
      create(:product)
      expect(Product.from_shopify.count).to eq(1)
    end
  end

  it "destroys variants when product destroyed" do
    product = create(:product, :with_variant)
    expect { product.destroy! }.to change(Variant, :count).by(-1)
  end
end
