namespace :bootstrap do
  desc "Live-deploy bootstrap: always re-registers Shopify webhooks; backfills Shopify data ONLY when the DB has none (or when FORCE_BACKFILL=true)."
  task run: :environment do
    log = ->(msg) { puts "[bootstrap] #{msg}" }

    # ── 1. Always (re-)register webhooks. Cheap; idempotent in the rake task. ──
    #     This keeps the integration live across redeploys and Render URL changes.
    base = ENV["SHOPIFY_WEBHOOK_BASE_URL"].presence || ENV["WEBHOOK_BASE_URL"].presence
    if base
      ENV["WEBHOOK_BASE_URL"] = base   # the existing rake task reads WEBHOOK_BASE_URL
      log.call "Registering webhooks against #{base} ..."
      begin
        Rake::Task["shopify:register_webhooks"].invoke
      rescue => e
        warn "[bootstrap] webhook registration failed: #{e.class}: #{e.message} (continuing)"
      end
    else
      log.call "SHOPIFY_WEBHOOK_BASE_URL not set — skipping webhook registration"
    end

    # ── 2. Backfill — per-entity, independent checks. ──
    #     Each entity is pulled when its own table has nothing from Shopify
    #     (or when FORCE_BACKFILL=true). This way a deploy that imported only
    #     products on a previous run will still pick up customers/orders/inventory
    #     on the next run. Webhooks keep everything live afterwards.
    unless ENV["SHOPIFY_SHOP_DOMAIN"].present? && ENV["SHOPIFY_ADMIN_ACCESS_TOKEN"].present?
      log.call "Shopify creds not set — skipping data backfill"
      next
    end

    force  = ENV["FORCE_BACKFILL"].to_s.downcase == "true"
    client = ::Shopify::Client.new
    totals = { products: 0, customers: 0, orders: 0, inventory: nil, refunds: 0, fulfillments: 0 }

    # Returns the remote count from Shopify's lightweight /count.json endpoint.
    # Returns nil on error so the caller can fall back to "always pull".
    remote_count = lambda do |path, params: {}|
      body = client.get(path, params: params)
      body.is_a?(Hash) ? body["count"] : nil
    rescue => e
      log.call "  could not fetch #{path}: #{e.class}: #{e.message}"
      nil
    end

    # Decide whether to pull. Pulls when:
    #   • FORCE_BACKFILL=true, OR
    #   • we can't read the remote count (be safe → pull), OR
    #   • the local count is below the remote count (DB is incomplete).
    needs_pull = lambda do |label, local_count, remote|
      if force
        log.call "#{label}: FORCE_BACKFILL=true — pulling"
        true
      elsif remote.nil?
        log.call "#{label}: remote count unknown — pulling to be safe"
        true
      elsif local_count < remote
        log.call "#{label}: local=#{local_count} < remote=#{remote} — pulling missing rows"
        true
      else
        log.call "#{label}: local=#{local_count} >= remote=#{remote} — up to date, skipping"
        false
      end
    end

    # ── Products ──
    local_products  = Product.where.not(shopify_product_id: nil).count
    remote_products = remote_count.call("products/count.json")
    if needs_pull.call("Products", local_products, remote_products)
      log.call "Pulling products (streaming) ..."
      client.paginated_each("products.json", key: "products") do |p|
        begin
          Catalog::Shopify::ProductUpserter.call(p, from: :rest)
          totals[:products] += 1
          log.call "  products upserted: #{totals[:products]}" if (totals[:products] % 100).zero?
        rescue => e
          warn "[bootstrap] product #{p["id"]} failed: #{e.class}: #{e.message}"
        end
      end
      GC.start
    end

    # ── Customers ──
    local_customers =
      if Customer.column_names.include?("shopify_customer_id")
        Customer.where.not(shopify_customer_id: nil).count
      else
        0
      end
    remote_customers = remote_count.call("customers/count.json")
    if needs_pull.call("Customers", local_customers, remote_customers)
      log.call "Pulling customers (streaming) ..."
      client.paginated_each("customers.json", key: "customers") do |c|
        begin
          Crm::Shopify::CustomerUpserter.call(c)
          totals[:customers] += 1
          log.call "  customers upserted: #{totals[:customers]}" if (totals[:customers] % 100).zero?
        rescue => e
          warn "[bootstrap] customer #{c["id"]} failed: #{e.class}: #{e.message}"
        end
      end
      GC.start
    end

    # ── Orders (includes line items, fulfillments, refunds inside payload) ──
    local_orders  = Order.where.not(shopify_order_id: nil).count
    remote_orders = remote_count.call("orders/count.json", params: { status: "any" })
    if needs_pull.call("Orders", local_orders, remote_orders)
      log.call "Pulling orders (status=any, streaming) ..."
      client.paginated_each("orders.json", key: "orders", params: { status: "any" }) do |o|
        begin
          Sales::Shopify::OrderUpserter.call(o, from: :rest)
          totals[:orders] += 1

          # Fulfillments and refunds are nested in the order payload — replay them
          # through their dedicated upserters so all derived state lands in the DB.
          Array(o["fulfillments"]).each do |f|
            begin
              Shipping::Shopify::FulfillmentUpserter.call(f.merge("order_id" => o["id"]))
              totals[:fulfillments] += 1
            rescue => e
              warn "[bootstrap] fulfillment #{f["id"]} failed: #{e.class}: #{e.message}"
            end
          end

          Array(o["refunds"]).each do |r|
            begin
              Sales::Shopify::RefundUpserter.call(r)
              totals[:refunds] += 1
            rescue => e
              warn "[bootstrap] refund #{r["id"]} failed: #{e.class}: #{e.message}"
            end
          end

          log.call "  orders upserted: #{totals[:orders]}" if (totals[:orders] % 50).zero?
          GC.start if (totals[:orders] % 100).zero?
        rescue => e
          warn "[bootstrap] order #{o["id"]} failed: #{e.class}: #{e.message}"
        end
      end
      GC.start
    end

    # ── Cleanup demo fulfillments/refunds that were incorrectly seeded for
    #    real Shopify orders. The seeds.rb used to create BST-DEMO-* records
    #    for ALL fulfilled orders, blocking the real Shopify data from being
    #    pulled. This one-time cleanup removes those stale records so the
    #    catch-up passes below can fetch the real data.
    fake_fulfillment_ids = Fulfillment
      .joins(:order)
      .where("fulfillments.tracking_number LIKE 'BST-DEMO-%'")
      .where.not(orders: { shopify_order_id: nil })
      .pluck(:id)
    if fake_fulfillment_ids.any?
      FulfillmentLineItem.where(fulfillment_id: fake_fulfillment_ids).delete_all
      Fulfillment.where(id: fake_fulfillment_ids).delete_all
      log.call "Removed #{fake_fulfillment_ids.size} stale demo fulfillments from Shopify orders"
    end

    fake_refund_ids = Refund
      .joins(:order)
      .where(note: "Returned via Estebdal")
      .where(shopify_refund_id: nil)
      .where.not(orders: { shopify_order_id: nil })
      .pluck(:id)
    if fake_refund_ids.any?
      RefundLineItem.where(refund_id: fake_refund_ids).delete_all
      Refund.where(id: fake_refund_ids).delete_all
      log.call "Removed #{fake_refund_ids.size} stale demo refunds from Shopify orders"
    end

    # ── Fulfillments catch-up ──
    # Runs independently of the orders block. Detects orders that should have
    # fulfillment records locally but don't, then batch-fetches those orders
    # from Shopify (up to 250 per request) to upsert the missing fulfillments.
    orders_missing_fulfillments =
      if force
        Order.where.not(shopify_order_id: nil).pluck(:shopify_order_id)
      else
        Order.where.not(shopify_order_id: nil)
             .where.not(fulfillment_status: [nil, "unfulfilled"])
             .where.not(id: Fulfillment.select(:order_id))
             .pluck(:shopify_order_id)
      end

    if orders_missing_fulfillments.any?
      log.call "Fulfillments catch-up: #{orders_missing_fulfillments.size} orders missing fulfillments — fetching ..."
      orders_missing_fulfillments.each_slice(250) do |ids_batch|
        begin
          body = client.get("orders.json", params: { ids: ids_batch.join(","), limit: 250, status: "any" })
          Array(body["orders"]).each do |o|
            Array(o["fulfillments"]).each do |f|
              begin
                Shipping::Shopify::FulfillmentUpserter.call(f.merge("order_id" => o["id"]))
                totals[:fulfillments] += 1
              rescue => e
                warn "[bootstrap] fulfillment #{f["id"]} (catch-up) failed: #{e.class}: #{e.message}"
              end
            end
          end
        rescue => e
          warn "[bootstrap] fulfillments batch #{ids_batch.first}.. failed: #{e.class}: #{e.message}"
        end
      end
      log.call "  fulfillments caught up: #{totals[:fulfillments]}"
    else
      log.call "Fulfillments: all up to date — skipping catch-up"
    end

    # ── Refunds catch-up ──
    # Same pattern: find orders with refunded financial status that have no
    # local Refund rows, then batch-fetch to upsert the missing refunds.
    orders_missing_refunds =
      if force
        Order.where.not(shopify_order_id: nil).pluck(:shopify_order_id)
      else
        Order.where.not(shopify_order_id: nil)
             .where(financial_status: %w[refunded partially_refunded])
             .where.not(id: Refund.select(:order_id))
             .pluck(:shopify_order_id)
      end

    if orders_missing_refunds.any?
      log.call "Refunds catch-up: #{orders_missing_refunds.size} orders missing refunds — fetching ..."
      orders_missing_refunds.each_slice(250) do |ids_batch|
        begin
          body = client.get("orders.json", params: { ids: ids_batch.join(","), limit: 250, status: "any" })
          Array(body["orders"]).each do |o|
            Array(o["refunds"]).each do |r|
              begin
                Sales::Shopify::RefundUpserter.call(r)
                totals[:refunds] += 1
              rescue => e
                warn "[bootstrap] refund #{r["id"]} (catch-up) failed: #{e.class}: #{e.message}"
              end
            end
          end
        rescue => e
          warn "[bootstrap] refunds batch #{ids_batch.first}.. failed: #{e.class}: #{e.message}"
        end
      end
      log.call "  refunds caught up: #{totals[:refunds]}"
    else
      log.call "Refunds: all up to date — skipping catch-up"
    end

    # ── Inventory (locations → warehouses → stock items) ──
    # Always run when forced or when we have no Shopify-linked warehouses /
    # no stock_items at all. The InventoryBackfill is itself idempotent.
    if force || Warehouse.where.not(shopify_location_id: nil).none? || StockItem.none?
      log.call "Pulling inventory (locations + levels) ..."
      begin
        stats = Inventory::Shopify::InventoryBackfill.call
        totals[:inventory] = stats
        log.call "  inventory: #{stats.inspect}"
      rescue => e
        warn "[bootstrap] inventory backfill failed: #{e.class}: #{e.message}"
      end
      GC.start
    else
      log.call "Inventory already populated — skipping (set FORCE_BACKFILL=true to re-pull)"
    end

    log.call "Done. #{totals.inspect}"
  end
end
