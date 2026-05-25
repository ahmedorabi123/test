module ShopifySyncState
  SYNC_STATE_FILE = Rails.root.join("tmp", "shopify_last_sync_at.txt").freeze
  INVENTORY_SYNC_STATE_FILE = Rails.root.join("tmp", "shopify_inventory_last_sync_at.txt").freeze

  def self.last_sync_at
    return nil unless SYNC_STATE_FILE.exist?
    Time.parse(SYNC_STATE_FILE.read.strip) rescue nil
  end

  def self.save(time)
    FileUtils.mkdir_p(SYNC_STATE_FILE.dirname)
    SYNC_STATE_FILE.write(time.utc.iso8601)
  end

  def self.inventory_last_sync_at
    return nil unless INVENTORY_SYNC_STATE_FILE.exist?
    Time.parse(INVENTORY_SYNC_STATE_FILE.read.strip) rescue nil
  end

  def self.inventory_due?(interval: 30.minutes)
    last_synced_at = inventory_last_sync_at
    last_synced_at.blank? || last_synced_at < interval.ago
  end

  def self.save_inventory(time)
    FileUtils.mkdir_p(INVENTORY_SYNC_STATE_FILE.dirname)
    INVENTORY_SYNC_STATE_FILE.write(time.utc.iso8601)
  end
end

namespace :bootstrap do
  BOOTSTRAP_LOCK_FILE = Rails.root.join("tmp", "bootstrap.lock").freeze

  desc "Live-deploy bootstrap: always re-registers Shopify webhooks; backfills Shopify data ONLY when the DB has none (or when FORCE_BACKFILL=true)."
  task run: :environment do
    log = ->(msg) { puts "[bootstrap] #{msg}" }

    # ── Exclusive file lock — prevent concurrent bootstrap runs ──────────────
    # Uses flock(LOCK_EX | LOCK_NB): returns false immediately if another
    # process already holds the lock, rather than blocking forever.
    FileUtils.mkdir_p(BOOTSTRAP_LOCK_FILE.dirname)
    lock_fh = File.open(BOOTSTRAP_LOCK_FILE, File::RDWR | File::CREAT, 0o644)
    unless lock_fh.flock(File::LOCK_EX | File::LOCK_NB)
      lock_fh.close
      log.call "Another bootstrap:run is already in progress (lock held) — skipping this invocation"
      next
    end

    # ── 1. Always (re-)register webhooks. Cheap; idempotent in the rake task. ──
    #     This keeps the integration live across redeploys and Render URL changes.
    base = ENV["SHOPIFY_WEBHOOK_BASE_URL"].presence || ENV["WEBHOOK_BASE_URL"].presence
    if base
      log.call "Registering webhooks against #{base} ..."
      begin
        wh_client = ::Shopify::Client.new
        # Skip GDPR compliance topics — Shopify only accepts them via the
        # app's config, not the REST webhooks endpoint.
        topics = Shopify::EventNormalizer::SUPPORTED_TOPICS.keys - %w[
          customers/data_request customers/redact shop/redact fulfillments/cancelled
        ]
        existing  = wh_client.get("webhooks.json").fetch("webhooks", []).index_by { |w| w["topic"] }
        topics.each do |topic|
          callback = "#{base}/webhooks/shopify/#{topic}"
          if (current = existing[topic])
            if current["address"] == callback
              puts "=  #{topic}  (already registered)"
              next
            else
              wh_client.delete("webhooks/#{current["id"]}.json")
              puts "-  #{topic}  (deleted stale registration)"
            end
          end
          wh_client.post("webhooks.json", payload: { webhook: { topic: topic, address: callback, format: "json" } })
          puts "+  #{topic}  -> #{callback}"
        rescue => e
          warn "!  #{topic}  FAILED: #{e.class}: #{e.message}"
        end
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
    totals = { products: 0, customers: 0, orders: 0, inventory: nil, fulfillments: 0 }

    # Returns the remote count from Shopify's lightweight /count.json endpoint.
    # Returns nil on error so the caller can fall back to "always pull".
    remote_count = lambda do |path, params: {}|
      body = client.get(path, params: params)
      body.is_a?(Hash) ? body["count"] : nil
    rescue => e
      log.call "  could not fetch #{path}: #{e.class}: #{e.message}"
      nil
    end

    # Decide whether to do a full pull.
    # Full pulls are expensive — only trigger on the very first run (local==0).
    # After that, bootstrap:catchup (updated_at_min) handles all incremental
    # updates: new records, edits, status changes, etc.
    #
    # Use FORCE_BACKFILL=true to re-pull everything regardless.
    needs_pull = lambda do |label, local_count, _remote|
      if force
        log.call "#{label}: FORCE_BACKFILL=true — pulling"
        true
      elsif local_count == 0
        log.call "#{label}: local=0 — first-time pull"
        true
      else
        log.call "#{label}: local=#{local_count} — already populated, incremental catchup will handle updates"
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

    # ── Orders (includes line items and fulfillments inside payload) ──
    local_orders  = Order.where.not(shopify_order_id: nil).count
    remote_orders = remote_count.call("orders/count.json", params: { status: "any" })
    if needs_pull.call("Orders", local_orders, remote_orders)
      log.call "Pulling orders (status=any, streaming) ..."
      client.paginated_each("orders.json", key: "orders", params: { status: "any" }) do |o|
        begin
          Sales::Shopify::OrderUpserter.call(o, from: :rest)
          totals[:orders] += 1

          # Fulfillments are nested in the order payload — replay them through
          # their dedicated upserter so derived state lands in the DB.
          Array(o["fulfillments"]).each do |f|
            begin
              Shipping::Shopify::FulfillmentUpserter.call(f.merge("order_id" => o["id"]))
              totals[:fulfillments] += 1
            rescue => e
              warn "[bootstrap] fulfillment #{f["id"]} failed: #{e.class}: #{e.message}"
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

    # ── Cleanup demo fulfillments that were incorrectly seeded for
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

    child_totals = Shopify::Reconcile::MissingChildren.call(client: client, force: force, log: log, warn_prefix: "[bootstrap]")
    totals[:fulfillments] += child_totals[:fulfillments]

    # ── Collections (custom + smart + collects memberships) ──
    local_collections  = Collection.where.not(shopify_collection_id: nil).count
    remote_custom_col  = remote_count.call("custom_collections/count.json")
    remote_smart_col   = remote_count.call("smart_collections/count.json")
    remote_collections = (remote_custom_col || 0) + (remote_smart_col || 0)
    if needs_pull.call("Collections", local_collections, remote_collections)
      log.call "Pulling custom collections ..."
      client.paginated_each("custom_collections.json", key: "custom_collections") do |c|
        begin
          Catalog::Shopify::CollectionUpserter.call(c, kind: :custom)
          totals[:collections] = (totals[:collections] || 0) + 1
        rescue => e
          warn "[bootstrap] custom_collection #{c["id"]} failed: #{e.class}: #{e.message}"
        end
      end

      log.call "Pulling smart collections ..."
      client.paginated_each("smart_collections.json", key: "smart_collections") do |c|
        begin
          Catalog::Shopify::CollectionUpserter.call(c, kind: :smart)
          totals[:collections] = (totals[:collections] || 0) + 1
        rescue => e
          warn "[bootstrap] smart_collection #{c["id"]} failed: #{e.class}: #{e.message}"
        end
      end

      log.call "Pulling collects (product memberships) ..."
      client.paginated_each("collects.json", key: "collects") do |collect|
        begin
          col = Collection.find_by(shopify_collection_id: collect["collection_id"].to_i)
          prd = Product.find_by(shopify_product_id: collect["product_id"].to_i)
          if col && prd
            cp = CollectionProduct.find_or_create_by!(collection: col, product: prd)
            cp.update_column(:position, collect["position"].to_i) if collect["position"]
          end
        rescue => e
          warn "[bootstrap] collect #{collect["id"]} failed: #{e.class}: #{e.message}"
        end
      end
      GC.start
      log.call "  collections: #{totals[:collections] || 0}"
    else
      log.call "Collections: up to date — skipping"
    end

    # ── Inventory (locations → warehouses → stock items) ──
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

    # ── Incremental catch-up: fetch records updated since last sync ──
    # This handles the case where the system was offline and records were
    # changed in Shopify (status updates, address changes, new items, etc.)
    # but no webhook was received. Runs after the count-based checks.
    sync_started_at = Time.current
    Rake::Task["bootstrap:catchup"].reenable rescue nil
    Rake::Task["bootstrap:catchup"].invoke
    ShopifySyncState.save(sync_started_at)

    # ── Accounting backfill: post journals for orders/fulfillments missing them ──
    # Idempotent — each handler checks its own idempotency key. Only triggers on first
    # run (when no sale journals exist) to avoid per-order DB probes on every restart.
    if JournalEntry.none? && Order.where(financial_status: %w[paid partially_refunded refunded]).exists?
      log.call "No journal entries found — running accounting backfill..."
      Rake::Task["bootstrap:backfill_accounting"].reenable rescue nil
      Rake::Task["bootstrap:backfill_accounting"].invoke
    else
      log.call "Accounting: journals already present — skipping full backfill"
    end

    log.call "Done. #{totals.inspect}"
  ensure
    # Always release the lock when finished (or on error)
    lock_fh&.flock(File::LOCK_UN)
    lock_fh&.close
  end

  desc "Incremental catch-up: fetch all Shopify records updated since last sync."
  task catchup: :environment do
    log = ->(msg) { puts "[catchup] #{msg}" }

    unless ENV["SHOPIFY_SHOP_DOMAIN"].present? && ENV["SHOPIFY_ADMIN_ACCESS_TOKEN"].present?
      log.call "Shopify creds not set — skipping"
      next
    end

    # Determine the sync baseline:
    #   1. Use the saved timestamp if it exists.
    #   2. Fall back to MAX(shopify_synced_at or updated_at) across key tables —
    #      this covers the case where the DB was restored from a backup and
    #      the tmp file doesn't exist.
    last_sync = ShopifySyncState.last_sync_at
    unless last_sync
      candidates = []
      candidates << Order.maximum(:updated_at)
      candidates << Customer.maximum(:updated_at)
      candidates << Product.maximum(:updated_at)
      last_sync = candidates.compact.min
    end

    unless last_sync
      log.call "No previous sync timestamp — skipping incremental catch-up (first run uses count-based bootstrap)"
      next
    end

    # Add a small overlap buffer to avoid missing records due to clock skew
    since = (last_sync - 2.minutes).utc.iso8601
    log.call "Fetching records updated since #{since} ..."

    client  = ::Shopify::Client.new
    totals  = { products: 0, customers: 0, orders: 0, fulfillments: 0, inventory: nil }
    sync_started_at = Time.current

    # ── Updated products ──
    begin
      client.paginated_each("products.json", key: "products",
                            params: { updated_at_min: since, limit: 250 }) do |p|
        Catalog::Shopify::ProductUpserter.call(p, from: :rest)
        totals[:products] += 1
      rescue => e
        warn "[catchup] product #{p["id"]} failed: #{e.class}: #{e.message}"
      end
      log.call "  products: #{totals[:products]} updated"
    rescue => e
      warn "[catchup] products fetch failed: #{e.class}: #{e.message}"
    end
    GC.start

    # ── Updated customers ──
    begin
      client.paginated_each("customers.json", key: "customers",
                            params: { updated_at_min: since, limit: 250 }) do |c|
        Crm::Shopify::CustomerUpserter.call(c)
        totals[:customers] += 1
      rescue => e
        warn "[catchup] customer #{c["id"]} failed: #{e.class}: #{e.message}"
      end
      log.call "  customers: #{totals[:customers]} updated"
    rescue => e
      warn "[catchup] customers fetch failed: #{e.class}: #{e.message}"
    end
    GC.start

    # ── Updated orders (+ nested fulfillments) ──
    begin
      client.paginated_each("orders.json", key: "orders",
                            params: { updated_at_min: since, status: "any", limit: 250 }) do |o|
        Sales::Shopify::OrderUpserter.call(o, from: :rest)
        totals[:orders] += 1

        Array(o["fulfillments"]).each do |f|
          Shipping::Shopify::FulfillmentUpserter.call(f.merge("order_id" => o["id"]))
          totals[:fulfillments] += 1
        rescue => e
          warn "[catchup] fulfillment #{f["id"]} failed: #{e.class}: #{e.message}"
        end

        GC.start if (totals[:orders] % 100).zero?
      rescue => e
        warn "[catchup] order #{o["id"]} failed: #{e.class}: #{e.message}"
      end
      log.call "  orders: #{totals[:orders]} updated, #{totals[:fulfillments]} fulfillments"
    rescue => e
      warn "[catchup] orders fetch failed: #{e.class}: #{e.message}"
    end
    GC.start

    child_totals = Shopify::Reconcile::MissingChildren.call(client: client, force: false, log: log, warn_prefix: "[catchup]")
    totals[:fulfillments] += child_totals[:fulfillments]
    GC.start

    if ShopifySyncState.inventory_due?
      begin
        stats = Inventory::Shopify::InventoryBackfill.call
        totals[:inventory] = stats
        ShopifySyncState.save_inventory(sync_started_at)
        log.call "  inventory: #{stats.inspect}"
      rescue => e
        warn "[catchup] inventory fetch failed: #{e.class}: #{e.message}"
      end
      GC.start
    else
      log.call "  inventory: recently synced - skipping"
    end

    ShopifySyncState.save(sync_started_at)

    log.call "Incremental catch-up done. #{totals.inspect}"
  end

  desc "Restore the latest (or named) DB backup then apply migrations and catch up with Shopify."
  task :restore_and_catchup, [:filename] => :environment do |_, args|
    log = ->(msg) { puts "[restore_and_catchup] #{msg}" }

    dir = Rails.root.join("db", "backups")
    dump_file = if args[:filename].present?
                  Pathname.new(args[:filename]).absolute? ?
                    Pathname.new(args[:filename]) :
                    dir.join(args[:filename])
                else
                  dir.glob("*.dump").sort.last
                end

    abort "[restore_and_catchup] No backup file found in #{dir}" unless dump_file&.exist?

    log.call "Restoring from #{dump_file.basename} ..."
    # Remove the saved sync timestamp so catchup uses the DB's own updated_at
    ShopifySyncState::SYNC_STATE_FILE.delete if ShopifySyncState::SYNC_STATE_FILE.exist?

    # Invoke db:restore
    ENV["FILENAME"] = dump_file.to_s
    Rake::Task["db:restore"].reenable rescue nil
    Rake::Task["db:restore"].invoke(dump_file.basename.to_s)

    log.call "Running pending migrations ..."
    Rake::Task["db:migrate"].reenable rescue nil
    Rake::Task["db:migrate"].invoke

    # Reconnect after restore
    ActiveRecord::Base.establish_connection

    log.call "Re-seeding users, roles, permissions and chart of accounts ..."
    Rake::Task["db:seed"].reenable rescue nil
    Rake::Task["db:seed"].invoke

    log.call "Starting Shopify catch-up ..."
    Rake::Task["bootstrap:catchup"].reenable rescue nil
    Rake::Task["bootstrap:catchup"].invoke

    log.call "Running accounting backfill after restore ..."
    Rake::Task["bootstrap:backfill_accounting"].reenable rescue nil
    Rake::Task["bootstrap:backfill_accounting"].invoke

    ShopifySyncState.save(Time.current)
    log.call "Done."
  end

  # ────────────────────────────────────────────────────────────────────────────
  # bootstrap:backfill_accounting
  # Idempotent: posts sale journal entries for every existing
  # order that is still missing one.
  # Safe to run multiple times — each handler checks its own idempotency key.
  # ────────────────────────────────────────────────────────────────────────────
  desc "Backfill accounting journal entries for all orders and fulfillments."
  task backfill_accounting: :environment do
    log = ->(msg) { puts "[backfill_accounting] #{msg}" }

    # ── 1. Sale journals for paid / partially_refunded / refunded orders ──────
    # PostSaleJournalHandler now accepts all three statuses (sale DID happen).
    sale_scope = Order.where(financial_status: %w[paid partially_refunded refunded])
    sale_total = sale_scope.count
    log.call "Checking #{sale_total} orders for missing sale journals..."
    posted_s = 0; skipped_s = 0; errors_s = 0
    sale_scope.find_each(batch_size: 200) do |order|
      next if JournalEntry.exists?(idempotency_key: "sale-journal-#{order.id}")
      begin
        result = Accounting::PostSaleJournalHandler.call(order)
        result ? (posted_s += 1) : (skipped_s += 1)
      rescue => e
        errors_s += 1
        Rails.logger.warn "[backfill_accounting] sale #{order.id}: #{e.message}"
      end
    end
    log.call "  sale journals: #{posted_s} posted, #{skipped_s} skipped (zero-amount), #{errors_s} errors"

    total_new = posted_s
    log.call "Accounting backfill done. #{total_new} new journal entries created."
  end

  # ────────────────────────────────────────────────────────────────────────────
  # bootstrap:backfill_inventory
  # Re-pulls Shopify inventory levels into StockItem records.
  # Run this after products/variants are populated (bootstrap:run handles that).
  # Safe to run multiple times — StockSyncService updates in-place.
  # ────────────────────────────────────────────────────────────────────────────
  desc "Backfill inventory stock levels from Shopify (locations + inventory_levels)."
  task backfill_inventory: :environment do
    log = ->(msg) { puts "[backfill_inventory] #{msg}" }

    unless ENV["SHOPIFY_SHOP_DOMAIN"].present? && ENV["SHOPIFY_ADMIN_ACCESS_TOKEN"].present?
      log.call "Shopify creds not set — skipping"
      next
    end

    log.call "Running Shopify inventory backfill..."
    begin
      stats = Inventory::Shopify::InventoryBackfill.call
      log.call "Done. #{stats.inspect}"
    rescue => e
      warn "[backfill_inventory] failed: #{e.class}: #{e.message}"
    end
  end
end
