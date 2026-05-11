require "rails_helper"

RSpec.describe Inventory::ConsumeCostLayers do
  let(:warehouse) { create(:warehouse) }
  let(:variant) { create(:variant, cost_per_item: 99.0) }
  let(:stock_item) { create(:stock_item, variant: variant, warehouse: warehouse, quantity_on_hand: 10) }

  it "consumes open layers FIFO and stores a breakdown on the reference" do
    first = Inventory::RecordCostLayer.call(stock_item: stock_item, quantity: 3, unit_cost: 5.00, source: stock_item)
    second = Inventory::RecordCostLayer.call(stock_item: stock_item, quantity: 5, unit_cost: 7.00, source: stock_item)
    fulfillment_line_item = create(:fulfillment, status: "success").fulfillment_line_items.create!(quantity: 4)

    result = described_class.call(stock_item: stock_item, quantity: 4, reference: fulfillment_line_item)

    expect(result.total_cost).to eq(22.0)
    expect(first.reload.qty_remaining).to eq(0)
    expect(second.reload.qty_remaining).to eq(4)
    expect(fulfillment_line_item.reload.cost_breakdown.map { |row| row["quantity"] }).to eq([3, 1])
  end

  it "uses the variant resolver for uncovered quantities" do
    Inventory::RecordCostLayer.call(stock_item: stock_item, quantity: 1, unit_cost: 5.00, source: stock_item)

    result = described_class.call(stock_item: stock_item, quantity: 3)

    expect(result.total_cost).to eq(203.0)
    expect(result.layers_used.last[:source]).to eq(:variant_cost_per_item)
  end
end