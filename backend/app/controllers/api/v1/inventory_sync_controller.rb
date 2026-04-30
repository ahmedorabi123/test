module Api
  module V1
    class InventorySyncController < ApplicationController
      include Pundit::Authorization

      # POST /api/v1/inventory/shopify_backfill
      # Triggers a synchronous inventory backfill from Shopify.
      def shopify_backfill
        authorize StockItem, :create?
        stats = Inventory::Shopify::InventoryBackfill.call
        AuditLog.record(user: current_user, action: "inventory.shopify_backfill",
                        subject: nil, diff: stats)
        render json: { data: stats }
      rescue StandardError => e
        Rails.logger.error "[InventorySyncController] backfill failed: #{e.message}"
        render_error(500, "internal", e.message)
      end
    end
  end
end
