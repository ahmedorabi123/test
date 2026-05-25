class AddShopifyMirrorQuantitiesToInventory < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    add_column :stock_items, :shopify_quantity_on_hand, :integer unless column_exists?(:stock_items, :shopify_quantity_on_hand)
    add_column :stock_items, :shopify_quantity_committed, :integer unless column_exists?(:stock_items, :shopify_quantity_committed)
    add_column :stock_items, :shopify_last_synced_at, :datetime unless column_exists?(:stock_items, :shopify_last_synced_at)

    add_column :stock_movements, :movement_scope, :string, null: false, default: "system" unless column_exists?(:stock_movements, :movement_scope)
    add_column :stock_movements, :committed_delta, :integer unless column_exists?(:stock_movements, :committed_delta)
    add_column :stock_movements, :committed_snapshot_before, :integer unless column_exists?(:stock_movements, :committed_snapshot_before)
    add_column :stock_movements, :committed_snapshot_after, :integer unless column_exists?(:stock_movements, :committed_snapshot_after)

    unless index_exists?(:stock_movements, %i[reference_type reference_id movement_scope], name: "index_stock_movements_on_reference_and_scope")
      add_index :stock_movements,
        %i[reference_type reference_id movement_scope],
        name: "index_stock_movements_on_reference_and_scope",
        algorithm: :concurrently
    end
    unless index_exists?(:stock_movements, %i[movement_scope reason], name: "index_stock_movements_on_scope_and_reason")
      add_index :stock_movements,
        %i[movement_scope reason],
        name: "index_stock_movements_on_scope_and_reason",
        algorithm: :concurrently
    end

    safety_assured do
      execute <<~SQL.squish
        UPDATE stock_items
        SET shopify_quantity_on_hand = stock_items.quantity_on_hand,
            shopify_quantity_committed = stock_items.quantity_reserved
        FROM variants, warehouses
        WHERE stock_items.variant_id = variants.id
          AND stock_items.warehouse_id = warehouses.id
          AND variants.shopify_inventory_item_id IS NOT NULL
          AND warehouses.shopify_location_id IS NOT NULL
          AND stock_items.shopify_quantity_on_hand IS NULL
      SQL
    end
  end

  def down
    remove_index :stock_movements, name: "index_stock_movements_on_scope_and_reason", algorithm: :concurrently if index_exists?(:stock_movements, name: "index_stock_movements_on_scope_and_reason")
    remove_index :stock_movements, name: "index_stock_movements_on_reference_and_scope", algorithm: :concurrently if index_exists?(:stock_movements, name: "index_stock_movements_on_reference_and_scope")

    remove_column :stock_movements, :committed_snapshot_after if column_exists?(:stock_movements, :committed_snapshot_after)
    remove_column :stock_movements, :committed_snapshot_before if column_exists?(:stock_movements, :committed_snapshot_before)
    remove_column :stock_movements, :committed_delta if column_exists?(:stock_movements, :committed_delta)
    remove_column :stock_movements, :movement_scope if column_exists?(:stock_movements, :movement_scope)

    remove_column :stock_items, :shopify_last_synced_at if column_exists?(:stock_items, :shopify_last_synced_at)
    remove_column :stock_items, :shopify_quantity_committed if column_exists?(:stock_items, :shopify_quantity_committed)
    remove_column :stock_items, :shopify_quantity_on_hand if column_exists?(:stock_items, :shopify_quantity_on_hand)
  end
end
