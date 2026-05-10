require "rails_helper"

RSpec.describe StockMovement, type: :model do
  let(:variant)    { create(:variant) }
  let(:warehouse)  { create(:warehouse) }
  let(:stock_item) { create(:stock_item, variant: variant, warehouse: warehouse, quantity_on_hand: 0) }

  let(:base) { { stock_item: stock_item, snapshot_before: 0, snapshot_after: 5, delta: 5 } }

  describe "validations" do
    it "requires delta to be an integer" do
      m = StockMovement.new(base.merge(delta: nil, reason: "received"))
      expect(m).not_to be_valid
    end

    it "rejects unknown reason" do
      m = StockMovement.new(base.merge(reason: "magic"))
      expect(m).not_to be_valid
    end

    it "accepts every canonical reason" do
      StockMovement::REASONS.each do |r|
        m = StockMovement.new(base.merge(reason: r))
        expect(m).to be_valid, "expected #{r} to be valid"
      end
    end
  end

  describe "immutability" do
    it "freezes after persistence (when reloaded)" do
      m = create(:stock_movement, stock_item: stock_item, reason: "received",
                 snapshot_before: 0, snapshot_after: 5, delta: 5)
      reloaded = StockMovement.find(m.id)
      expect(reloaded).to be_frozen
      expect { reloaded.delta = 99 }.to raise_error(/can't modify frozen|FrozenError/)
    end
  end
end
