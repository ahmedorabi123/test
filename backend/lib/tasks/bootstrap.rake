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

    # ── Products ──
    if force || Product.where.not(shopify_product_id: nil).none?
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
    else
      log.call "Products already populated — skipping (FORCE_BACKFILL=true to re-pull)"
    end

    # ── Customers ──
    customers_present =
      if Customer.column_names.include?("shopify_customer_id")
        Customer.where.not(shopify_customer_id: nil).any?
      else
        Customer.any?
      end
    if force || !customers_present
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
    else
      log.call "Customers already populated — skipping"
    end

    # ── Orders (includes line items, fulfillments, refunds inside payload) ──
    if force || Order.where.not(shopify_order_id: nil).none?
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
    else
      log.call "Orders already populated — skipping"
    end

    # ── Inventory (locations → warehouses → stock items) ──
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
      log.call "Inventory already populated — skipping"
    end

    log.call "Done. #{totals.inspect}"
  end
end
