require "rails_helper"

RSpec.describe Inventory::WriteMovement do
  let(:warehouse)  { create(:warehouse) }
  let(:product)    { create(:product) }
  let(:variant)    { create(:variant, product: product) }
  let(:stock_item) { create(:stock_item, variant: variant, warehouse: warehouse, quantity_on_hand: 20) }

  it "applies a negative delta, writes a StockMovement, and updates QoH" do
    expect {
      described_class.call(stock_item: stock_item, delta: -3, reason: "fulfilled")
    }.to change(StockMovement, :count).by(1)

    sm = StockMovement.last
    expect(sm.delta).to eq(-3)
    expect(sm.reason).to eq("fulfilled")
    expect(sm.snapshot_before).to eq(20)
    expect(sm.snapshot_after).to eq(17)
    expect(stock_item.reload.quantity_on_hand).to eq(17)
  end

  it "applies a positive delta (returns/restock)" do
    described_class.call(stock_item: stock_item, delta: 5, reason: "returned")
    expect(stock_item.reload.quantity_on_hand).to eq(25)
    expect(StockMovement.last.reason).to eq("returned")
  end

  it "is a no-op when delta is zero" do
    expect {
      described_class.call(stock_item: stock_item, delta: 0, reason: "adjusted")
    }.not_to change(StockMovement, :count)
  end

  it "clamps to zero instead of going negative by default" do
    described_class.call(stock_item: stock_item, delta: -99, reason: "fulfilled")
    expect(stock_item.reload.quantity_on_hand).to eq(0)
    expect(StockMovement.last.delta).to eq(-20)
  end

  it "raises in strict mode when delta would go negative" do
    expect {
      described_class.call(stock_item: stock_item, delta: -99, reason: "fulfilled", strict: true)
    }.to raise_error(Inventory::WriteMovement::InsufficientStockError)
  end

  it "records the reference polymorphically" do
    ref = create(:order)
    described_class.call(stock_item: stock_item, delta: -1, reason: "fulfilled", reference: ref)
    sm = StockMovement.last
    expect(sm.reference_type).to eq("Order")
    expect(sm.reference_id).to eq(ref.id.to_s)
  end
end
