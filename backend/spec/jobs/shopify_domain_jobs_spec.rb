require "rails_helper"

# These jobs are thin wrappers — assert each delegates to the right service
# with the right arguments. The services themselves are unit-tested elsewhere.
RSpec.describe "Shopify domain dispatch jobs" do
  let(:payload) { { "id" => 1, "name" => "#1001" } }

  it "Sales::HandleShopifyOrderJob → OrderUpserter (from: :webhook)" do
    expect(Sales::Shopify::OrderUpserter).to receive(:call).with(payload, from: :webhook)
    Sales::HandleShopifyOrderJob.perform_now(payload)
  end

  it "Sales::HandleShopifyRefundJob → RefundUpserter" do
    expect(Sales::Shopify::RefundUpserter).to receive(:call).with(payload)
    Sales::HandleShopifyRefundJob.perform_now(payload)
  end

  it "Shipping::HandleShopifyFulfillmentJob → FulfillmentUpserter" do
    expect(Shipping::Shopify::FulfillmentUpserter).to receive(:call).with(payload)
    Shipping::HandleShopifyFulfillmentJob.perform_now(payload)
  end

  it "Crm::HandleShopifyCustomerJob → CustomerUpserter" do
    expect(Crm::Shopify::CustomerUpserter).to receive(:call).with(payload)
    Crm::HandleShopifyCustomerJob.perform_now(payload)
  end

  it "Inventory::HandleShopifyInventoryJob → StockSyncService" do
    expect(Inventory::Shopify::StockSyncService).to receive(:call).with(payload)
    Inventory::HandleShopifyInventoryJob.perform_now(payload)
  end

  it "Catalog::HandleShopifyProductJob → ProductUpserter (from: :webhook)" do
    expect(Catalog::Shopify::ProductUpserter).to receive(:call).with(payload, from: :webhook)
    Catalog::HandleShopifyProductJob.perform_now(payload)
  end

  it "Catalog::HandleShopifyCollectionJob → CollectionUpserter (with kind)" do
    expect(Catalog::Shopify::CollectionUpserter).to receive(:call).with(payload, kind: :smart)
    Catalog::HandleShopifyCollectionJob.perform_now(payload, kind: "smart")
  end

  describe "Inventory::ProvisionStockItemsJob" do
    it "no-ops when variant is missing" do
      expect(Inventory::ProvisionStockItems).not_to receive(:call)
      Inventory::ProvisionStockItemsJob.perform_now("00000000-0000-0000-0000-000000000000")
    end

    it "delegates to ProvisionStockItems with the variant" do
      variant = create(:variant)
      expect(Inventory::ProvisionStockItems).to receive(:call).with(variant: variant)
      Inventory::ProvisionStockItemsJob.perform_now(variant.id)
    end
  end
end
