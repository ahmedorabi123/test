require "rails_helper"

RSpec.describe Shopify::Origin do
  it "marks Shopify-linked records as locally read-only" do
    product = create(:product, :from_shopify)

    expect(product).to be_shopify_origin
    expect(product.update(title: "Local edit")).to be(false)
    expect(product.errors[:base]).to include(Shopify::Origin::READ_ONLY_MESSAGE)
  end

  it "allows trusted Shopify sync code to update Shopify-origin records" do
    product = create(:product, :from_shopify, title: "Old")

    Shopify::Origin.without_read_only do
      product.update!(title: "Synced title")
    end

    expect(product.reload.title).to eq("Synced title")
  end

  it "blocks local destruction of Shopify-origin records" do
    product = create(:product, :from_shopify)

    expect(product.destroy).to be(false)
    expect(Product.exists?(product.id)).to be(true)
  end

  it "treats stock rows for Shopify variants at Shopify locations as read-only" do
    variant = create(:variant, :from_shopify)
    warehouse = create(:warehouse, shopify_location_id: 123456)
    stock_item = create(:stock_item, variant: variant, warehouse: warehouse)

    expect(stock_item).to be_shopify_origin
    expect(stock_item.update(quantity_on_hand: 99)).to be(false)
  end
end