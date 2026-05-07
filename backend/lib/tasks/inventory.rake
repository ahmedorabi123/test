namespace :inventory do
  desc "Provision missing zero-quantity stock_items for every variant in active owned warehouses. Safe to rerun."
  task provision_missing_stock_items: :environment do
    total = 0
    warehouses = Warehouse.active.own
    puts "[inventory:provision_missing_stock_items] warehouses=#{warehouses.count} variants=#{Variant.count}"

    Variant.find_each do |variant|
      before = variant.stock_items.count
      Inventory::ProvisionStockItems.call(variant: variant, warehouses: warehouses)
      total += variant.stock_items.count - before
    end

    puts "[inventory:provision_missing_stock_items] created=#{total}"
  end

  desc "Backfill stock_reservations from open orders and recount quantity_reserved. Safe to rerun."
  task backfill_reservations: :environment do
    puts "[inventory:backfill_reservations] Releasing existing active reservation rows..."
    StockReservation.active.update_all(status: "released", updated_at: Time.current) if defined?(StockReservation)

    open_orders = Order.where(status: %w[pending processing]).includes(line_items: :variant)
    puts "[inventory:backfill_reservations] Processing #{open_orders.count} open order(s)..."

    created = 0
    errors = 0
    open_orders.find_each.with_index(1) do |order, idx|
      before = StockReservation.active.count
      Inventory::SyncOrderReservations.call(order)
      created += StockReservation.active.count - before
      print "." if (idx % 50).zero?
    rescue Inventory::Oversold => e
      errors += 1
      warn "\n[inventory:backfill_reservations] order=#{order.id} oversold: #{e.message}"
    rescue StandardError => e
      errors += 1
      warn "\n[inventory:backfill_reservations] order=#{order.id} failed: #{e.class}: #{e.message}"
    end

    StockItem.find_each { |stock_item| Inventory::Reservations::RecountStockItem.call(stock_item) }

    puts "\n[inventory:backfill_reservations] Done. active=#{StockReservation.active.count}, created_delta=#{created}, errors=#{errors}"
  end

  desc "Defensive cleanup: release active reservations belonging to cancelled/refunded orders."
  task sweep_orphan_reservations: :environment do
    scope = StockReservation.active.joins(order_line_item: :order)
                            .where(orders: { status: %w[cancelled refunded] })
    stock_item_ids = scope.distinct.pluck(:stock_item_id)
    count = scope.update_all(status: "released", updated_at: Time.current)
    stock_item_ids.each do |stock_item_id|
      stock_item = StockItem.find_by(id: stock_item_id)
      Inventory::Reservations::RecountStockItem.call(stock_item) if stock_item
    end
    puts "[inventory:sweep_orphan_reservations] released=#{count}"
  end

  desc "Backward-compatible alias for the new reservation ledger backfill."
  task rebuild_reservations: :backfill_reservations do
  end
end
