require "rails_helper"

RSpec.describe Imports::ShowroomSalesImporter do
  let!(:warehouse) { create(:warehouse, code: "SHOWROOM-1") }
  let!(:variant)   { create(:variant, sku: "SR-SKU-1", price: 100) }
  let!(:stock)     { create(:stock_item, variant: variant, warehouse: warehouse, quantity_on_hand: 100) }

  let(:csv) do
    <<~CSV
      Order #,SKU,Quantity,Price,Warehouse Code,Customer Name
      SR-1001,SR-SKU-1,2,100.00,SHOWROOM-1,Walk-in
    CSV
  end

  describe ".commit" do
    it "creates a manual order tagged for idempotency" do
      result = described_class.commit(StringIO.new(csv))
      expect(result[:created]).to eq(1)
      expect(result[:errors]).to be_empty
      order = Order.last
      expect(order.notes).to include("[showroom_csv:SHOWROOM-1:SR-1001:")
    end

    it "skips re-import of identical CSV (idempotent)" do
      described_class.commit(StringIO.new(csv))
      expect(Order.count).to eq(1)

      result = described_class.commit(StringIO.new(csv))
      expect(result[:created]).to eq(0)
      expect(result[:errors].first[:message]).to include("already imported")
      expect(Order.count).to eq(1)
    end

    it "treats different line items as a different report (creates a new order)" do
      described_class.commit(StringIO.new(csv))

      different_csv = <<~CSV
        Order #,SKU,Quantity,Price,Warehouse Code,Customer Name
        SR-1001,SR-SKU-1,3,100.00,SHOWROOM-1,Walk-in
      CSV
      result = described_class.commit(StringIO.new(different_csv))
      expect(result[:created]).to eq(1)
      expect(Order.count).to eq(2)
    end
  end
end
