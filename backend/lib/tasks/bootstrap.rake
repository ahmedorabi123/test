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

    # ── 2. Backfill — only when needed. ──
    unless ENV["SHOPIFY_SHOP_DOMAIN"].present? && ENV["SHOPIFY_ADMIN_ACCESS_TOKEN"].present?
      log.call "Shopify creds not set — skipping data backfill"
      next
    end

    force            = ENV["FORCE_BACKFILL"].to_s.downcase == "true"
    shopify_products = Product.where.not(shopify_product_id: nil).count
    shopify_orders   = Order.where.not(shopify_order_id: nil).count

    if !force && (shopify_products.positive? || shopify_orders.positive?)
      log.call "DB already has Shopify data (products=#{shopify_products}, orders=#{shopify_orders}). " \
               "Skipping backfill — webhooks will keep it in sync. " \
               "Set FORCE_BACKFILL=true on Render to re-pull everything."
      next
    end

    log.call(force ? "FORCE_BACKFILL=true — re-pulling all Shopify data" : "DB empty of Shopify data — running first-time backfill")

    client = ::Shopify::Client.new

    log.call "Pulling products ..."
    products = client.paginated("products.json", key: "products")
    log.call "  fetched #{products.size}; upserting..."
    products.each do |p|
      Catalog::Shopify::ProductUpserter.call(p, from: :rest)
    rescue => e
      warn "[bootstrap] product #{p["id"]} failed: #{e.class}: #{e.message}"
    end

    log.call "Pulling customers ..."
    customers = client.paginated("customers.json", key: "customers")
    log.call "  fetched #{customers.size}; upserting..."
    customers.each do |c|
      CRM::Shopify::CustomerUpserter.call(c)
    rescue => e
      warn "[bootstrap] customer #{c["id"]} failed: #{e.class}: #{e.message}"
    end

    log.call "Pulling orders (status=any) ..."
    orders = client.paginated("orders.json", key: "orders", params: { status: "any" })
    log.call "  fetched #{orders.size}; upserting..."
    orders.each do |o|
      Sales::Shopify::OrderUpserter.call(o, from: :rest)
    rescue => e
      warn "[bootstrap] order #{o["id"]} failed: #{e.class}: #{e.message}"
    end

    log.call "Done. Products=#{products.size} Customers=#{customers.size} Orders=#{orders.size}"
  end
end
