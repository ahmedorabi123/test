require "rails_helper"

RSpec.describe Inventory::PostStockTransfer do
  let(:user)    { create(:user, :admin) }
  let(:from_wh) { create(:warehouse, code: "WH-A") }
  let(:to_wh)   { create(:warehouse, code: "WH-B") }
  let(:product) { create(:product) }
  let(:v1)      { create(:variant, product: product, sku: "V1") }
  let(:v2)      { create(:variant, product: product, sku: "V2") }

  before do
    create(:stock_item, variant: v1, warehouse: from_wh, quantity_on_hand: 10)
    create(:stock_item, variant: v2, warehouse: from_wh, quantity_on_hand: 5)
  end

  def call(lines:, header_extras: {}, actor: user)
    described_class.call(
      header_attrs: {
        from_warehouse_id: from_wh.id,
        to_warehouse_id:   to_wh.id,
        reason:            "transfer"
      }.merge(header_extras),
      lines: lines,
      actor: actor
    )
  end

  it "creates a posted StockTransfer with one line per variant and paired movements" do
    transfer = call(lines: [
      { variant_id: v1.id, quantity: 3 },
      { variant_id: v2.id, quantity: 2 }
    ])

    expect(transfer).to be_a(StockTransfer)
    expect(transfer.status).to eq("posted")
    expect(transfer.reference).to match(/\ATR-\d{4}-\d{4}\z/)
    expect(transfer.stock_transfer_lines.count).to eq(2)
    expect(transfer.posted_by_user_id).to eq(user.id)

    expect(StockMovement.where(reference_type: "StockTransferLine").count).to eq(4) # 2 lines * 2 sides

    expect(StockItem.find_by(variant: v1, warehouse: from_wh).quantity_on_hand).to eq(7)
    expect(StockItem.find_by(variant: v1, warehouse: to_wh).quantity_on_hand).to eq(3)
    expect(StockItem.find_by(variant: v2, warehouse: from_wh).quantity_on_hand).to eq(3)
    expect(StockItem.find_by(variant: v2, warehouse: to_wh).quantity_on_hand).to eq(2)
  end

  it "rolls back ALL lines when one fails (insufficient stock)" do
    expect {
      call(lines: [
        { variant_id: v1.id, quantity: 3 },
        { variant_id: v2.id, quantity: 999 }
      ])
    }.to raise_error(described_class::InsufficientStock)

    expect(StockTransfer.count).to eq(0)
    expect(StockTransferLine.count).to eq(0)
    expect(StockMovement.count).to eq(0)
    expect(StockItem.find_by(variant: v1, warehouse: from_wh).quantity_on_hand).to eq(10)
  end

  it "rejects same source and destination" do
    expect {
      described_class.call(
        header_attrs: { from_warehouse_id: from_wh.id, to_warehouse_id: from_wh.id, reason: "transfer" },
        lines: [{ variant_id: v1.id, quantity: 1 }],
        actor: user
      )
    }.to raise_error(described_class::InvalidInput, /differ/)
  end

  it "rejects empty lines" do
    expect { call(lines: []) }.to raise_error(described_class::InvalidInput, /at least one/)
  end

  it "rejects duplicate variant rows" do
    expect {
      call(lines: [
        { variant_id: v1.id, quantity: 1 },
        { variant_id: v1.id, quantity: 2 }
      ])
    }.to raise_error(described_class::InvalidInput, /duplicate/)
  end

  it "rejects non-positive quantities" do
    expect {
      call(lines: [{ variant_id: v1.id, quantity: 0 }])
    }.to raise_error(described_class::InvalidInput, /positive/)
  end

  it "rejects Shopify-origin source warehouse" do
    shopify_wh = create(:warehouse, code: "WH-SHOP", shopify_location_id: 999)
    create(:stock_item, variant: v1, warehouse: shopify_wh, quantity_on_hand: 10)
    expect {
      described_class.call(
        header_attrs: { from_warehouse_id: shopify_wh.id, to_warehouse_id: to_wh.id, reason: "transfer" },
        lines: [{ variant_id: v1.id, quantity: 1 }],
        actor: user
      )
    }.to raise_error(described_class::ReadOnlyOrigin, /Shopify/)
    expect(StockTransfer.count).to eq(0)
  end

  it "rejects Shopify-origin destination warehouse" do
    shopify_wh = create(:warehouse, code: "WH-SHOP", shopify_location_id: 999)
    expect {
      described_class.call(
        header_attrs: { from_warehouse_id: from_wh.id, to_warehouse_id: shopify_wh.id, reason: "transfer" },
        lines: [{ variant_id: v1.id, quantity: 1 }],
        actor: user
      )
    }.to raise_error(described_class::ReadOnlyOrigin)
  end

  it "honours reservations on the source side" do
    si = StockItem.find_by(variant: v1, warehouse: from_wh)
    si.update!(quantity_reserved: 9) # available = 1
    expect {
      call(lines: [{ variant_id: v1.id, quantity: 5 }])
    }.to raise_error(described_class::InsufficientStock) do |err|
      expect(err.available).to eq(1)
      expect(err.requested).to eq(5)
      expect(err.variant_id).to eq(v1.id)
    end
  end

  it "generates a unique sequential reference per year" do
    t1 = call(lines: [{ variant_id: v1.id, quantity: 1 }])
    t2 = call(lines: [{ variant_id: v2.id, quantity: 1 }])
    expect(t1.reference).not_to eq(t2.reference)
    expect(t1.reference.split("-").last.to_i).to be < t2.reference.split("-").last.to_i
  end
end
