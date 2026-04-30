require "rails_helper"

RSpec.describe StockItem, type: :model do
  it "validates quantity_on_hand >= 0" do
    expect(build(:stock_item, quantity_on_hand: -1)).not_to be_valid
  end

  it "enforces unique variant+warehouse pair" do
    si = create(:stock_item)
    dup = build(:stock_item, variant: si.variant, warehouse: si.warehouse)
    expect(dup).not_to be_valid
  end

  it "#available returns on_hand minus reserved" do
    si = build(:stock_item, quantity_on_hand: 10, quantity_reserved: 3)
    expect(si.available).to eq(7)
  end

  it "#available never goes below 0" do
    si = build(:stock_item, quantity_on_hand: 2, quantity_reserved: 10)
    expect(si.available).to eq(0)
  end

  it "#low_stock? is true when available <= threshold" do
    expect(build(:stock_item, quantity_on_hand: 3, quantity_reserved: 0, low_stock_threshold: 5)).to be_low_stock
    expect(build(:stock_item, quantity_on_hand: 10, quantity_reserved: 0, low_stock_threshold: 5)).not_to be_low_stock
  end

  it "low_stock scope" do
    create(:stock_item, quantity_on_hand: 2, quantity_reserved: 0, low_stock_threshold: 5)
    create(:stock_item, quantity_on_hand: 20, quantity_reserved: 0, low_stock_threshold: 5)
    expect(StockItem.low_stock.count).to eq(1)
  end
end
