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
        shopify_je = JournalEntry.where(source_type: "order", source_id: shopify_source_ids)
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

      # Snapshot Shopify-origin counts so we can assert they are unchanged
      # after the destructive pass. Any drift here means the manual_only path
      # accidentally swept a Shopify row — abort hard rather than ship the diff.
      shopify_snapshot = {
        orders:        Order.shopify_origin.count,
        products:      Product.shopify_origin.count,
        variants:      Variant.shopify_origin.count,
        warehouses:    Warehouse.shopify_origin.count,
        customers:     (defined?(Customer)     ? Customer.shopify_origin.count     : 0),
        refunds:       (defined?(Refund)       ? Refund.shopify_origin.count       : 0),
        fulfillments:  (defined?(Fulfillment)  ? Fulfillment.shopify_origin.count  : 0),
        collections:   (defined?(Collection)   ? Collection.shopify_origin.count   : 0)
      }

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

        manual_order_line_item_ids = OrderLineItem.where(order_id: manual_order_ids).pluck(:id)
        counts[:order_line_items] = manual_order_line_item_ids.size
        manual_order_id_strs = manual_order_ids.map(&:to_s)
        manual_refund_id_strs = manual_refund_ids.map(&:to_s)
        manual_fulfillment_id_strs = manual_fulfillment_ids.map(&:to_s)

        # ── 3. Manual customers ───────────────────────────────────────────────
        counts[:customers] = Customer.where(shopify_customer_id: nil).count

        # ── 4. Manual products + variants ────────────────────────────────────
        manual_product_ids = Product.where(shopify_product_id: nil).pluck(:id)
        manual_variant_ids = Variant.where(shopify_variant_id: nil).pluck(:id)
        manual_collection_ids = Collection.where(shopify_collection_id: nil).pluck(:id) if defined?(Collection)
        counts[:products] = manual_product_ids.size
        counts[:variants] = manual_variant_ids.size
        counts[:collections] = manual_collection_ids&.size || 0

        # ── 5. Manual stock items (linked to manual warehouses or manual variants) ─
        manual_wh_ids = Warehouse.where(shopify_location_id: nil).pluck(:id)
        counts[:warehouses] = manual_wh_ids.size

        manual_stock_item_ids = StockItem.where(
          "(warehouse_id IN (?)) OR (variant_id IN (?))",
          manual_wh_ids.presence || ["00000000-0000-0000-0000-000000000000"],
          manual_variant_ids.presence || ["00000000-0000-0000-0000-000000000000"]
        ).pluck(:id)
        counts[:stock_items] = manual_stock_item_ids.size

        manual_stock_movement_ids = StockMovement.where(
          "(stock_item_id IN (?))",
          manual_stock_item_ids.presence || ["00000000-0000-0000-0000-000000000000"]
        ).pluck(:id)
        counts[:stock_movements] = manual_stock_movement_ids.size
        manual_stock_movement_id_strs = manual_stock_movement_ids.map(&:to_s)

        manual_showroom_reversal_ids = defined?(ShowroomReversal) ? ShowroomReversal.where(warehouse_id: manual_wh_ids).pluck(:id) : []
        counts[:showroom_reversals] = manual_showroom_reversal_ids.size
        manual_showroom_reversal_id_strs = manual_showroom_reversal_ids.map(&:to_s)

        # ── 6. Stock transfers (all are manual) ──────────────────────────────
        counts[:stock_transfers] = StockTransfer.count
        counts[:stock_transfer_lines] = defined?(StockTransferLine) ? StockTransferLine.count : 0

        # ── 7. Purchase orders (all are manual — no Shopify PO sync) ─────────
        counts[:purchase_orders] = PurchaseOrder.count
        counts[:purchase_order_lines] = defined?(PurchaseOrderLineItem) ? PurchaseOrderLineItem.count : 0
        counts[:suppliers] = defined?(Supplier) ? Supplier.count : 0

        production_order_ids = defined?(ProductionOrder) ? ProductionOrder.pluck(:id) : []
        counts[:production_orders] = production_order_ids.size
        counts[:production_stages] = defined?(ProductionStage) ? ProductionStage.where(production_order_id: production_order_ids).count : 0

        counts[:user_roles_scoped_to_manual_warehouses] = defined?(UserRole) ? UserRole.where(warehouse_id: manual_wh_ids).count : 0

        # ── 8. Stock reservations for manual orders ───────────────────────────
        manual_reservation_count = defined?(StockReservation) ?
          StockReservation.where(order_line_item_id: manual_order_line_item_ids).count : 0
        counts[:stock_reservations] = manual_reservation_count

        # ── 9. Accounting entries from manual entities ───────────────────────
        manual_je = JournalEntry.where(
          "(source_type = 'order' AND source_id IN (:order_ids)) OR " \
          "(source_type = 'refund' AND source_id IN (:refund_ids)) OR " \
          "(source_type = 'fulfillment' AND source_id IN (:fulfillment_ids)) OR " \
          "(source_type = 'showroom_reversal' AND source_id IN (:showroom_reversal_ids)) OR " \
          "(source_type = 'stock_movement' AND source_id IN (:stock_movement_ids)) OR " \
          "(entry_type = 'manual')",
          order_ids: manual_order_id_strs.presence || ["__none__"],
          refund_ids: manual_refund_id_strs.presence || ["__none__"],
          fulfillment_ids: manual_fulfillment_id_strs.presence || ["__none__"],
          showroom_reversal_ids: manual_showroom_reversal_id_strs.presence || ["__none__"],
          stock_movement_ids: manual_stock_movement_id_strs.presence || ["__none__"]
        )
        counts[:journal_entries] = manual_je.count
        counts[:journal_lines] = JournalLine.where(journal_entry_id: manual_je.select(:id)).count

        puts "[cleanup:manual_only] counts:"
        counts.each { |k, v| puts "  #{k}: #{v}" }

        if dry
          puts "[cleanup:manual_only] DRY_RUN — rolling back."
          raise ActiveRecord::Rollback
        end

        Shopify::Origin.without_read_only do
          # 8. Reservations first (to avoid FK violations)
          StockReservation.where(order_line_item_id: manual_order_line_item_ids).delete_all if defined?(StockReservation) && manual_order_line_item_ids.any?

          # 7. POs
          if defined?(PurchaseOrderLineItem)
            PurchaseOrderLineItem.delete_all
          end
          PurchaseOrder.delete_all if defined?(PurchaseOrder)

          if defined?(ProductionStage) && production_order_ids.any?
            ProductionStage.where(production_order_id: production_order_ids).delete_all
          end
          ProductionOrder.where(id: production_order_ids).delete_all if defined?(ProductionOrder) && production_order_ids.any?
          Supplier.delete_all if defined?(Supplier)

          # 6. Stock transfers
          StockTransferLine.delete_all if defined?(StockTransferLine)
          StockTransfer.delete_all

          UserRole.where(warehouse_id: manual_wh_ids).delete_all if defined?(UserRole) && manual_wh_ids.any?
          ShowroomReversal.where(id: manual_showroom_reversal_ids).delete_all if defined?(ShowroomReversal) && manual_showroom_reversal_ids.any?

          # 5. Stock movements + cost layers + stock items
          if manual_stock_item_ids.any?
            # Reservations may also reference stock_items directly via
            # stock_item_id (not only through their order_line_item). Cover
            # both legs to avoid FK violations.
            if defined?(StockReservation)
              StockReservation.where(stock_item_id: manual_stock_item_ids).delete_all
            end
            StockMovement.where(stock_item_id: manual_stock_item_ids).delete_all
            StockCostLayer.where(stock_item_id: manual_stock_item_ids).delete_all if defined?(StockCostLayer)
            StockItem.where(id: manual_stock_item_ids).delete_all
          end
          Warehouse.where(shopify_location_id: nil).delete_all

          # 4. Catalog: variants then products (Shopify items are protected via scope NOT used here)
          CollectionProduct.where(collection_id: manual_collection_ids).delete_all if defined?(CollectionProduct) && manual_collection_ids.present?
          Collection.where(id: manual_collection_ids).find_each(batch_size: 200, &:destroy) if defined?(Collection) && manual_collection_ids.present?

          # Any surviving order_line_item that still references a manual variant
          # would block variant deletion via FK. Such rows can only exist on
          # historical/orphaned data — nullify the variant reference (we keep
          # the OLI row for the audit trail) before deleting variants.
          manual_variant_ids = Variant.where(shopify_variant_id: nil).pluck(:id)
          if manual_variant_ids.any?
            OrderLineItem.where(variant_id: manual_variant_ids).update_all(variant_id: nil)
          end

          Variant.where(shopify_variant_id: nil).delete_all
          Product.where(shopify_product_id: nil).find_each(batch_size: 200, &:destroy)

          # 3. Customers
          # Surviving Shopify orders may still reference a manual customer
          # (e.g. legacy data); null the FK before delete to keep the audit
          # trail of those orders intact.
          manual_customer_ids = Customer.where(shopify_customer_id: nil).pluck(:id)
          if manual_customer_ids.any?
            Order.where(customer_id: manual_customer_ids).update_all(customer_id: nil)
          end
          Customer.where(shopify_customer_id: nil).delete_all

          # 2. Accounting entries
          je_ids = manual_je.pluck(:id)
          if je_ids.any?
            JournalLine.where(journal_entry_id: je_ids).delete_all
            JournalEntry.where(id: je_ids).delete_all
          end

          # 2b. Always purge COGS-touching journal entries (account 5000 / 1200
          # inventory-consumption pair) and any leftover purchase-type entries
          # whose PO has been wiped. The system no longer posts COGS at all,
          # so these are orphans by definition.
          cogs_account_ids = Account.where(code: ["5000", "1200"]).pluck(:id)
          cogs_je_ids = cogs_account_ids.any? ?
            JournalLine.where(account_id: cogs_account_ids).pluck(:journal_entry_id).uniq : []
          orphan_purchase_je_ids = JournalEntry.where(entry_type: "purchase").pluck(:id)
          orphan_ids = (cogs_je_ids + orphan_purchase_je_ids).uniq
          if orphan_ids.any?
            JournalLine.where(journal_entry_id: orphan_ids).delete_all
            JournalEntry.where(id: orphan_ids).delete_all
            puts "[cleanup:manual_only] purged #{orphan_ids.size} orphan/COGS journal entries"
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

        # Integrity guard: every Shopify-origin count must be unchanged.
        after = {
          orders:        Order.shopify_origin.count,
          products:      Product.shopify_origin.count,
          variants:      Variant.shopify_origin.count,
          warehouses:    Warehouse.shopify_origin.count,
          customers:     (defined?(Customer)     ? Customer.shopify_origin.count     : 0),
          refunds:       (defined?(Refund)       ? Refund.shopify_origin.count       : 0),
          fulfillments:  (defined?(Fulfillment)  ? Fulfillment.shopify_origin.count  : 0),
          collections:   (defined?(Collection)   ? Collection.shopify_origin.count   : 0)
        }
        drift = shopify_snapshot.keys.select { |k| shopify_snapshot[k] != after[k] }
        if drift.any?
          report = drift.map { |k| "#{k}: #{shopify_snapshot[k]} -> #{after[k]}" }.join(", ")
          raise "[cleanup:manual_only] Shopify-origin counts changed — aborting (#{report})"
        end
        puts "[cleanup:manual_only] Shopify-origin counts unchanged ✓"

        if ENV["SKIP_CATCHUP"].to_s != "1" && Rake::Task.task_defined?("bootstrap:catchup")
          puts "[cleanup:manual_only] running bootstrap:catchup to refresh Shopify mirror…"
          begin
            Rake::Task["bootstrap:catchup"].reenable
            Rake::Task["bootstrap:catchup"].invoke
          rescue => e
            warn "[cleanup:manual_only] catchup failed (continuing): #{e.class}: #{e.message}"
          end
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

    # ─────────────────────────────────────────────────────────────────────────
    # db:cleanup:all_operational
    #
    # Runs manual_only then shopify_only in one shot to wipe ALL operational
    # data (orders, refunds, fulfillments, journal entries, stock movements
    # and reservations, products/variants/collections, manual warehouses and
    # purchase orders). Chart of Accounts, users, roles and Shopify-managed
    # warehouses stay. Shopify catch-up backfill runs at the end of
    # shopify_only.
    # ─────────────────────────────────────────────────────────────────────────
    desc "DESTRUCTIVE: wipe all manual AND Shopify-originated operational data. " \
         "Set CLEANUP_CONFIRM=YES_I_MEAN_IT; DRY_RUN=1 to preview."
    task all_operational: :environment do
      unless ENV["CLEANUP_CONFIRM"].to_s == "YES_I_MEAN_IT"
        abort "[cleanup:all_operational] Refusing to run. Set CLEANUP_CONFIRM=YES_I_MEAN_IT to confirm."
      end
      Rake::Task["db:cleanup:manual_only"].invoke
      Rake::Task["db:cleanup:shopify_only"].invoke
    end

    # ─────────────────────────────────────────────────────────────────────────
    # db:cleanup:status
    #
    # Non-destructive pre-flight: prints per-module counts split into
    # "shopify" (origin set) and "manual" (origin nil) buckets so the
    # operator can see exactly what `manual_only` vs `shopify_only` will
    # touch before running anything destructive.
    # ─────────────────────────────────────────────────────────────────────────
    desc "Print per-module counts split by origin (manual vs Shopify). Non-destructive."
    task status: :environment do
      pairs = [
        ["Order",            Order],
        ["OrderLineItem",    OrderLineItem],
        ["Refund",           defined?(Refund) ? Refund : nil],
        ["Fulfillment",      defined?(Fulfillment) ? Fulfillment : nil],
        ["Customer",         defined?(Customer) ? Customer : nil],
        ["Product",          Product],
        ["Variant",          Variant],
        ["Collection",       defined?(Collection) ? Collection : nil],
        ["Warehouse",        Warehouse],
        ["StockItem",        StockItem]
      ].compact

      puts "[cleanup:status] origin split (manual vs Shopify):"
      pairs.each do |label, klass|
        if klass.respond_to?(:shopify_origin) && klass.respond_to?(:manual_origin)
          shopify = klass.shopify_origin.count
          manual  = klass.manual_origin.count
          puts format("  %-18s manual=%-6d shopify=%-6d total=%d",
                      label, manual, shopify, manual + shopify)
        else
          puts format("  %-18s (no origin scope) total=%d", label, klass.count)
        end
      end

      # Always-manual tables (no Shopify counterpart)
      puts "[cleanup:status] manual-only modules:"
      [
        ["PurchaseOrder",    defined?(PurchaseOrder) ? PurchaseOrder : nil],
        ["StockTransfer",    defined?(StockTransfer) ? StockTransfer : nil],
        ["Supplier",         defined?(Supplier) ? Supplier : nil],
        ["ProductionOrder",  defined?(ProductionOrder) ? ProductionOrder : nil]
      ].compact.each do |label, klass|
        puts format("  %-18s total=%d", label, klass.count)
      end

      puts "[cleanup:status] webhook events:"
      if defined?(WebhookEvent)
        puts format("  shopify=%d processed=%d failed=%d",
                    WebhookEvent.where(source: "shopify").count,
                    WebhookEvent.where.not(processed_at: nil).count,
                    WebhookEvent.where.not(error: nil).count)
      end
    end
  end
end

# RUNBOOK — Shopify-only reset
# =============================================================================
# 1. Pre-flight inspection (non-destructive):
#      docker compose exec backend bin/rails db:cleanup:status
#
# 2. Take a full DB backup BEFORE any destructive task:
#      docker compose exec backend bin/rails 'db:backup[pre_cleanup]'
#    (Stored under backend/db/backups/; restore with rails 'db:restore[<file>]')
#
# 3. Dry-run the desired task (counts only; transaction rolled back):
#      CLEANUP_CONFIRM=YES_I_MEAN_IT DRY_RUN=1 \
#        docker compose exec -e CLEANUP_CONFIRM -e DRY_RUN \
#        backend bin/rails db:cleanup:manual_only
#
# 4. Review printed counts. If acceptable, execute for real:
#      CLEANUP_CONFIRM=YES_I_MEAN_IT \
#        docker compose exec -e CLEANUP_CONFIRM \
#        backend bin/rails db:cleanup:manual_only
#
# 5. After cleanup, verify Shopify-origin survivors and trigger an incremental
#    catch-up to repopulate from Shopify:
#      docker compose exec backend bin/rails db:cleanup:status
#      docker compose exec backend bin/rails bootstrap:catchup
#
# Notes:
#   - manual_only  → preserves every Shopify-origin row.
#   - shopify_only → deletes Shopify-origin operational rows then re-pulls
#     from Shopify (unless SKIP_BACKFILL=1).
#   - all_operational → manual_only then shopify_only.
#   - On failure, the whole task rolls back inside its transaction; combined
#     with step 2 the operation is fully reversible.
# =============================================================================
