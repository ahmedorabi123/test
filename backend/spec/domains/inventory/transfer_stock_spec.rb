require "rails_helper"

RSpec.describe Inventory::TransferStock do
  let(:from_wh) { create(:warehouse) }
  let(:to_wh)   { create(:warehouse) }
  let(:product) { create(:product) }
  let(:variant) { create(:variant, product: product) }

  before do
    create(:stock_item, variant: variant, warehouse: from_wh, quantity_on_hand: 10)
  end

  it "moves units between warehouses and writes two paired movements" do
    expect {
      described_class.call(
        variant: variant, from_warehouse: from_wh, to_warehouse: to_wh,
        quantity: 4
      )
    }.to change(StockMovement, :count).by(2)

    from_si = StockItem.find_by(variant: variant, warehouse: from_wh)
    to_si   = StockItem.find_by(variant: variant, warehouse: to_wh)
    expect(from_si.quantity_on_hand).to eq(6)
    expect(to_si.quantity_on_hand).to eq(4)
  end

  it "creates the destination StockItem when missing" do
    expect(StockItem.where(variant: variant, warehouse: to_wh)).to be_empty
    described_class.call(
      variant: variant, from_warehouse: from_wh, to_warehouse: to_wh, quantity: 3
    )
    expect(StockItem.find_by(variant: variant, warehouse: to_wh).quantity_on_hand).to eq(3)
  end

  it "raises InsufficientStock when source lacks units (and rolls back)" do
    expect {
      described_class.call(
        variant: variant, from_warehouse: from_wh, to_warehouse: to_wh, quantity: 100
      )
    }.to raise_error(described_class::InsufficientStock)

    expect(StockItem.find_by(variant: variant, warehouse: from_wh).quantity_on_hand).to eq(10)
    expect(StockMovement.count).to eq(0)
  end

  it "rejects same-warehouse transfers" do
    expect {
      described_class.call(
        variant: variant, from_warehouse: from_wh, to_warehouse: from_wh, quantity: 1
      )
    }.to raise_error(ArgumentError, /must differ/)
  end

  it "rejects non-positive quantities" do
    expect {
      described_class.call(
        variant: variant, from_warehouse: from_wh, to_warehouse: to_wh, quantity: 0
      )
    }.to raise_error(ArgumentError, /positive/)
  end

  it "honours reserved stock and refuses to transfer beyond available" do
    si = StockItem.find_by(variant: variant, warehouse: from_wh)
    si.update!(quantity_reserved: 8)  # available = 10 - 8 = 2

    expect {
      described_class.call(
        variant: variant, from_warehouse: from_wh, to_warehouse: to_wh, quantity: 5
      )
    }.to raise_error(described_class::InsufficientStock, /only 2 available/)

    # Source state unchanged on failure.
    si.reload
    expect(si.quantity_on_hand).to eq(10)
    expect(si.quantity_reserved).to eq(8)
    expect(StockMovement.count).to eq(0)
  end

  it "permits transfers up to the available amount when stock is partly reserved" do
    si = StockItem.find_by(variant: variant, warehouse: from_wh)
    si.update!(quantity_reserved: 6)  # available = 4

    described_class.call(
      variant: variant, from_warehouse: from_wh, to_warehouse: to_wh, quantity: 4
    )

    si.reload
    expect(si.quantity_on_hand).to eq(6)
    expect(si.quantity_reserved).to eq(6) # reservations untouched
    expect(StockItem.find_by(variant: variant, warehouse: to_wh).quantity_on_hand).to eq(4)
  end
end
