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
