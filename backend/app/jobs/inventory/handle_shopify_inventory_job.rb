class Inventory::HandleShopifyInventoryJob < ApplicationJob
  queue_as :default

  def perform(payload)
    Inventory::Shopify::StockSyncService.call(payload)
  end
end
