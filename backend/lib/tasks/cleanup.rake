# frozen_string_literal: true

# Destructive cleanup task that DELETES all Shopify-origin data while preserving
# manual ERP-origin data (manual orders, manufacturing-produced products,
# warehouses created in ERP, suppliers, etc.).
#
# SAFETY:
#   - Refuses to run without `CLEANUP_CONFIRM=YES_I_MEAN_IT`.
#   - Pass `DRY_RUN=1` to print counts without deleting.
#   - Wraps everything in a single transaction; aborts on any failure.
#
# After deletion it triggers Shopify catch-up backfill so the database can be
# rebuilt cleanly from Shopify, then runs accounting integrity checks.

namespace :db do
  namespace :cleanup do
    desc "DESTRUCTIVE: delete Shopify-origin data (orders, products, variants, stock, refunds, journals). Set CLEANUP_CONFIRM=YES_I_MEAN_IT to run; DRY_RUN=1 to preview."
    task shopify_only: :environment do
      confirm = ENV["CLEANUP_CONFIRM"].to_s
      dry     = ENV["DRY_RUN"].to_s == "1"

      unless confirm == "YES_I_MEAN_IT"
        abort "[cleanup:shopify_only] Refusing to run. Set CLEANUP_CONFIRM=YES_I_MEAN_IT to confirm."
      end

      puts "[cleanup:shopify_only] mode=#{dry ? 'DRY_RUN' : 'EXECUTE'}"

      counts = {}

      ApplicationRecord.transaction do
        # 1. Shopify orders + dependent rows
        shopify_orders = Order.shopify_origin
        counts[:orders]            = shopify_orders.count
        counts[:order_line_items]  = OrderLineItem.where(order_id: shopify_orders.select(:id)).count
        counts[:fulfillments]      = Fulfillment.where(order_id: shopify_orders.select(:id)).count if defined?(Fulfillment)
        counts[:refunds]           = Refund.where(order_id: shopify_orders.select(:id)).count if defined?(Refund)
        counts[:reservations]      = Inventory::Reservation.where(order_id: shopify_orders.select(:id)).count if defined?(Inventory::Reservation)

        unless dry
          # FK-safe order: children first.
          Shopify::Origin.without_read_only do
            Inventory::Reservation.where(order_id: shopify_orders.select(:id)).delete_all if defined?(Inventory::Reservation)
            if defined?(Refund)
              refund_ids = Refund.where(order_id: shopify_orders.select(:id)).pluck(:id)
              RefundLineItem.where(refund_id: refund_ids).delete_all if defined?(RefundLineItem)
              Refund.where(id: refund_ids).delete_all
            end
            if defined?(Fulfillment)
              fulfillment_ids = Fulfillment.where(order_id: shopify_orders.select(:id)).pluck(:id)
              FulfillmentLineItem.where(fulfillment_id: fulfillment_ids).delete_all if defined?(FulfillmentLineItem)
              Fulfillment.where(id: fulfillment_ids).delete_all
            end
            OrderLineItem.where(order_id: shopify_orders.select(:id)).delete_all
            shopify_orders.delete_all
          end
        end

        # 2. Shopify-origin catalog (variants → products → collections)
        shopify_products = Product.shopify_origin
        shopify_variants = Variant.where(product_id: shopify_products.select(:id))
        counts[:products] = shopify_products.count
        counts[:variants] = shopify_variants.count
        counts[:collections] = Collection.shopify_origin.count

        unless dry
          Shopify::Origin.without_read_only do
            stock_item_ids = StockItem.where(variant_id: shopify_variants.select(:id)).pluck(:id)
            counts[:stock_items_deleted] = stock_item_ids.size
            Inventory::CostLayer.where(stock_item_id: stock_item_ids).delete_all if defined?(Inventory::CostLayer)
            StockItem.where(id: stock_item_ids).delete_all

            shopify_variants.delete_all
            shopify_products.find_each(batch_size: 200, &:destroy)
            Collection.shopify_origin.find_each(batch_size: 200, &:destroy)
          end
        end

        # 3. Shopify warehouses (locations) + any remaining stock_items there
        shopify_warehouses = Warehouse.shopify_origin
        counts[:warehouses] = shopify_warehouses.count
        unless dry
          Shopify::Origin.without_read_only do
            StockItem.where(warehouse_id: shopify_warehouses.select(:id)).delete_all
            shopify_warehouses.delete_all
          end
        end

        # 4. Shopify-sourced journal entries
        shopify_source_ids = Order.where.not(shopify_order_id: nil).pluck(:id).map(&:to_s)
        shopify_je = JournalEntry.where(source_type: "Order", source_id: shopify_source_ids)
        counts[:journal_entries] = shopify_je.count
        unless dry
          JournalLine.where(journal_entry_id: shopify_je.select(:id)).delete_all
          shopify_je.delete_all
        end

        # 5. Webhook & domain event audit trail tied to Shopify
        counts[:webhook_events] = WebhookEvent.where(source: "shopify").count if defined?(WebhookEvent)
        unless dry
          WebhookEvent.where(source: "shopify").delete_all if defined?(WebhookEvent)
        end

        puts "[cleanup:shopify_only] counts:"
        counts.each { |k, v| puts "  #{k}: #{v}" }

        if dry
          puts "[cleanup:shopify_only] DRY_RUN — rolling back."
          raise ActiveRecord::Rollback
        end
      end

      # 6. Recount stock items (post-deletion) so quantity_reserved and
      #    quantity_unavailable are consistent.
      if !dry && defined?(Inventory::Reservations::RecountStockItem)
        puts "[cleanup:shopify_only] recounting remaining stock items…"
        StockItem.find_each(batch_size: 500) do |si|
          Inventory::Reservations::RecountStockItem.call(si)
        end
      end

      # 7. Re-pull from Shopify so the system rebuilds itself.
      if !dry && ENV["SKIP_BACKFILL"].to_s != "1"
        puts "[cleanup:shopify_only] backfilling from Shopify…"
        Catalog::Shopify::ProductBackfillService.call if defined?(Catalog::Shopify::ProductBackfillService)
        Inventory::Shopify::StockSyncService.call    if defined?(Inventory::Shopify::StockSyncService)
        Sales::Shopify::OrderBackfillService.call    if defined?(Sales::Shopify::OrderBackfillService)
        Shopify::Reconcile::MissingChildren.call     if defined?(Shopify::Reconcile::MissingChildren)
      end

      # 8. Accounting integrity check.
      if !dry && defined?(Accounting::IntegrityChecker)
        puts "[cleanup:shopify_only] running accounting integrity check…"
        report = Accounting::IntegrityChecker.call
        if report[:errors].any?
          puts "[cleanup:shopify_only] accounting issues:"
          report[:errors].each { |e| puts "  - #{e}" }
        else
          puts "[cleanup:shopify_only] accounting OK"
        end
      end

      puts "[cleanup:shopify_only] done."
    end
  end
end
