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

    # ─────────────────────────────────────────────────────────────────────────
    # db:cleanup:manual_only
    #
    # DESTRUCTIVE: removes ALL manually created / testing data while keeping
    # every Shopify-originated row intact.
    #
    # What is "manual"?
    #   Orders:        shopify_order_id IS NULL
    #   Refunds:       shopify_refund_id IS NULL
    #   Products:      shopify_product_id IS NULL
    #   Variants:      shopify_variant_id IS NULL
    #   Customers:     shopify_customer_id IS NULL
    #   Warehouses:    shopify_location_id IS NULL
    #   StockItems:    linked to non-Shopify warehouse or variant
    #   StockMovements: reason in manual/adjustment/transfer/refund_restock
    #                   where the source object is manual
    #   PurchaseOrders: all (no Shopify sync for POs)
    #   AccountingEntries: source_type/source_id links to manual orders/refunds,
    #                      or entry_type = 'manual'
    #
    # SAFETY:
    #   - Requires CLEANUP_CONFIRM=YES_I_MEAN_IT
    #   - DRY_RUN=1 prints counts without deleting
    #   - Wrapped in a single transaction
    # ─────────────────────────────────────────────────────────────────────────
    desc "DESTRUCTIVE: delete ALL manually-created / test data while keeping Shopify data. " \
         "Set CLEANUP_CONFIRM=YES_I_MEAN_IT; DRY_RUN=1 to preview."
    task manual_only: :environment do
      confirm = ENV["CLEANUP_CONFIRM"].to_s
      dry     = ENV["DRY_RUN"].to_s == "1"

      unless confirm == "YES_I_MEAN_IT"
        abort "[cleanup:manual_only] Refusing to run. Set CLEANUP_CONFIRM=YES_I_MEAN_IT to confirm."
      end

      puts "[cleanup:manual_only] mode=#{dry ? 'DRY_RUN' : 'EXECUTE'}"
      counts = {}

      ApplicationRecord.transaction do
        # ── 1. Manual orders & all their dependents ──────────────────────────
        manual_order_ids = Order.where(shopify_order_id: nil).pluck(:id)
        counts[:orders] = manual_order_ids.size

        manual_refund_ids = Refund.where(shopify_refund_id: nil).pluck(:id)
        counts[:refunds] = manual_refund_ids.size
        counts[:refund_line_items] = RefundLineItem.where(refund_id: manual_refund_ids).count if manual_refund_ids.any?

        manual_fulfillment_ids = defined?(Fulfillment) ? Fulfillment.where(order_id: manual_order_ids, shopify_fulfillment_id: nil).pluck(:id) : []
        counts[:fulfillments] = manual_fulfillment_ids.size
        counts[:fulfillment_line_items] = defined?(FulfillmentLineItem) ? FulfillmentLineItem.where(fulfillment_id: manual_fulfillment_ids).count : 0

        counts[:order_line_items] = OrderLineItem.where(order_id: manual_order_ids).count

        # ── 2. Accounting entries from manual orders/refunds ─────────────────
        # Manual-order journal entries (source_type=Order, source not Shopify)
        manual_order_id_strs = manual_order_ids.map(&:to_s)
        manual_refund_id_strs = manual_refund_ids.map(&:to_s)
        manual_je = JournalEntry.where(
          "(source_type = 'order' AND source_id IN (?)) OR " \
          "(source_type = 'refund' AND source_id IN (?)) OR " \
          "(entry_type = 'manual')",
          manual_order_id_strs,
          manual_refund_id_strs
        )
        counts[:journal_entries]      = manual_je.count
        counts[:journal_lines]        = JournalLine.where(journal_entry_id: manual_je.select(:id)).count

        # ── 3. Manual customers ───────────────────────────────────────────────
        counts[:customers] = Customer.where(shopify_customer_id: nil).count

        # ── 4. Manual products + variants ────────────────────────────────────
        manual_product_ids = Product.where(shopify_product_id: nil).pluck(:id)
        manual_variant_ids = Variant.where(shopify_variant_id: nil).pluck(:id)
        counts[:products] = manual_product_ids.size
        counts[:variants] = manual_variant_ids.size

        # ── 5. Manual stock items (linked to manual warehouses or manual variants) ─
        manual_wh_ids = Warehouse.where(shopify_location_id: nil).pluck(:id)
        counts[:warehouses] = manual_wh_ids.size

        manual_stock_item_ids = StockItem.where(
          "(warehouse_id IN (?)) OR (variant_id IN (?))",
          manual_wh_ids.presence || ["__none__"],
          manual_variant_ids.presence || ["__none__"]
        ).pluck(:id)
        counts[:stock_items] = manual_stock_item_ids.size

        # Stock movements for manual stock items or from manual order sources
        counts[:stock_movements] = StockMovement.where(
          "(stock_item_id IN (?))",
          manual_stock_item_ids.presence || ["__none__"]
        ).count

        # ── 6. Stock transfers (all are manual) ──────────────────────────────
        counts[:stock_transfers] = StockTransfer.count
        counts[:stock_transfer_lines] = defined?(StockTransferLine) ? StockTransferLine.count : 0

        # ── 7. Purchase orders (all are manual — no Shopify PO sync) ─────────
        counts[:purchase_orders] = PurchaseOrder.count
        counts[:purchase_order_lines] = defined?(PurchaseOrderLineItem) ? PurchaseOrderLineItem.count : 0

        # ── 8. Stock reservations for manual orders ───────────────────────────
        manual_reservation_count = defined?(StockReservation) ?
          StockReservation.where(order_id: manual_order_ids).count : 0
        counts[:stock_reservations] = manual_reservation_count

        puts "[cleanup:manual_only] counts:"
        counts.each { |k, v| puts "  #{k}: #{v}" }

        if dry
          puts "[cleanup:manual_only] DRY_RUN — rolling back."
          raise ActiveRecord::Rollback
        end

        Shopify::Origin.without_read_only do
          # 8. Reservations first (to avoid FK violations)
          StockReservation.where(order_id: manual_order_ids).delete_all if defined?(StockReservation) && manual_order_ids.any?

          # 7. POs
          if defined?(PurchaseOrderLineItem)
            PurchaseOrderLineItem.delete_all
          end
          PurchaseOrder.delete_all if defined?(PurchaseOrder)

          # 6. Stock transfers
          StockTransferLine.delete_all if defined?(StockTransferLine)
          StockTransfer.delete_all

          # 5. Stock movements + cost layers + stock items
          if manual_stock_item_ids.any?
            StockMovement.where(stock_item_id: manual_stock_item_ids).delete_all
            StockCostLayer.where(stock_item_id: manual_stock_item_ids).delete_all if defined?(StockCostLayer)
            StockItem.where(id: manual_stock_item_ids).delete_all
          end
          Warehouse.where(shopify_location_id: nil).delete_all

          # 4. Catalog: variants then products (Shopify items are protected via scope NOT used here)
          Variant.where(shopify_variant_id: nil).delete_all
          Product.where(shopify_product_id: nil).find_each(batch_size: 200, &:destroy)

          # 3. Customers
          Customer.where(shopify_customer_id: nil).delete_all

          # 2. Accounting entries
          je_ids = manual_je.pluck(:id)
          if je_ids.any?
            JournalLine.where(journal_entry_id: je_ids).delete_all
            JournalEntry.where(id: je_ids).delete_all
          end

          # 1. Orders + dependents
          if manual_order_ids.any?
            RefundLineItem.where(refund_id: manual_refund_ids).delete_all
            Refund.where(id: manual_refund_ids).delete_all
            FulfillmentLineItem.where(fulfillment_id: manual_fulfillment_ids).delete_all if manual_fulfillment_ids.any? && defined?(FulfillmentLineItem)
            Fulfillment.where(id: manual_fulfillment_ids).delete_all if manual_fulfillment_ids.any? && defined?(Fulfillment)
            OrderLineItem.where(order_id: manual_order_ids).delete_all
            Order.where(id: manual_order_ids).delete_all
          end
        end

        puts "[cleanup:manual_only] deletion complete."
      end

      # Recount remaining stock items for consistency
      unless dry
        puts "[cleanup:manual_only] recounting remaining stock items…"
        StockItem.find_each(batch_size: 500) do |si|
          Inventory::Reservations::RecountStockItem.call(si) if defined?(Inventory::Reservations::RecountStockItem)
        end

        if defined?(Accounting::IntegrityChecker)
          puts "[cleanup:manual_only] running accounting integrity check…"
          report = Accounting::IntegrityChecker.call
          if report[:errors].any?
            puts "[cleanup:manual_only] accounting issues:"
            report[:errors].each { |e| puts "  - #{e}" }
          else
            puts "[cleanup:manual_only] accounting OK (#{report[:checked]} entries checked)"
          end
        end
      end

      puts "[cleanup:manual_only] done."
    end
  end
end
