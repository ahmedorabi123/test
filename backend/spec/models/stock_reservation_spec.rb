require "rails_helper"

RSpec.describe StockReservation, type: :model do
  let(:order)      { create(:order) }
  let(:line_item)  { create(:order_line_item, order: order) }
  let(:variant)    { create(:variant) }
  let(:warehouse)  { create(:warehouse) }
  let(:stock_item) { create(:stock_item, variant: variant, warehouse: warehouse) }

  let(:base) { { order_line_item: line_item, stock_item: stock_item, quantity: 1, status: "active" } }

  describe "validations" do
    it "requires quantity > 0" do
      expect(StockReservation.new(base.merge(quantity: 0))).not_to be_valid
      expect(StockReservation.new(base.merge(quantity: -1))).not_to be_valid
    end

    it "rejects non-canonical status" do
      expect(StockReservation.new(base.merge(status: "weird"))).not_to be_valid
    end

    it "accepts every canonical status" do
      StockReservation::STATUSES.each do |s|
        expect(StockReservation.new(base.merge(status: s))).to be_valid
      end
    end
  end

  describe "scopes" do
    it ".active / .released / .consumed partition by status" do
      a = StockReservation.create!(base.merge(status: "active"))
      r = StockReservation.create!(base.merge(status: "released"))
      c = StockReservation.create!(base.merge(status: "consumed"))
      expect(StockReservation.active).to contain_exactly(a)
      expect(StockReservation.released).to contain_exactly(r)
      expect(StockReservation.consumed).to contain_exactly(c)
    end
  end
end
