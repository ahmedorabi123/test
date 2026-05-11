namespace :inventory do
  desc "Backfill FIFO stock cost layers from received movements and current stock remainders"
  task backfill_cost_layers: :environment do
    created = 0

    StockMovement.where(reason: "received").includes(stock_item: :variant).find_each do |movement|
      stock_item = movement.stock_item
      next unless stock_item&.variant
      next if StockCostLayer.exists?(source_type: movement.class.name, source_id: movement.id.to_s)

      unit_cost = Catalog::VariantCostResolver.call(stock_item.variant).cost
      next if unit_cost.negative?

      Inventory::RecordCostLayer.call(
        stock_item: stock_item,
        quantity: movement.delta.to_i.abs,
        unit_cost: unit_cost,
        source: movement,
        received_at: movement.created_at,
        details: { backfill: true, movement_reason: movement.reason }
      )
      created += 1
    end

    StockItem.includes(:variant).find_each do |stock_item|
      next unless stock_item.variant
      open_qty = StockCostLayer.where(stock_item: stock_item).sum(:qty_remaining).to_i
      remainder = stock_item.quantity_on_hand.to_i - open_qty
      next if remainder <= 0

      result = Catalog::VariantCostResolver.call(stock_item.variant)
      next if result.zero?

      Inventory::RecordCostLayer.call(
        stock_item: stock_item,
        quantity: remainder,
        unit_cost: result.cost,
        source: stock_item,
        details: { backfill: true, source: result.source, reason: "on_hand_remainder" }
      )
      created += 1
    end

    puts "[inventory:backfill_cost_layers] created=#{created}"
  end
end