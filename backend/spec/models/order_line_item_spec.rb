require "rails_helper"

RSpec.describe OrderLineItem, type: :model do
  it "auto-calculates line_total from price × quantity − discount before save" do
    order = create(:order)
    item  = OrderLineItem.new(
      order: order, title: "Widget", quantity: 3, price: 10, total_discount: 5
    )
    item.save!
    expect(item.line_total).to eq(25) # (10*3) - 5
  end

  it "requires a positive quantity" do
    item = build(:order_line_item, quantity: 0)
    expect(item).not_to be_valid
  end

  it "links to a variant when provided" do
    variant = create(:variant)
    item    = create(:order_line_item, variant: variant)
    expect(item.variant).to eq(variant)
  end
end
