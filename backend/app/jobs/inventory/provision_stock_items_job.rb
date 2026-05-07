module Inventory
  class ProvisionStockItemsJob < ApplicationJob
    queue_as :default

    def perform(variant_id)
      variant = Variant.find_by(id: variant_id)
      return unless variant

      Inventory::ProvisionStockItems.call(variant: variant)
    end
  end
end