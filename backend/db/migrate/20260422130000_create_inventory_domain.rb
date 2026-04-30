class CreateInventoryDomain < ActiveRecord::Migration[8.0]
  def change
    # ─── Warehouses ────────────────────────────────────────────────────────────
    create_table :warehouses, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string  :name,       null: false
      t.string  :code,       null: false       # e.g. "WH-NY-01" — unique slug
      t.string  :address
      t.boolean :active,     null: false, default: true
      t.timestamps
    end
    add_index :warehouses, :code, unique: true

    # ─── Stock Items (variant × warehouse join) ─────────────────────────────────
    create_table :stock_items, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :variant,   null: false, type: :uuid, foreign_key: true
      t.references :warehouse, null: false, type: :uuid, foreign_key: true
      t.integer :quantity_on_hand,       null: false, default: 0
      t.integer :quantity_reserved,      null: false, default: 0
      t.integer :low_stock_threshold,    null: false, default: 5
      t.bigint  :shopify_inventory_level_id   # synced from Shopify
      t.timestamps
    end
    add_index :stock_items, %i[variant_id warehouse_id], unique: true
    add_index :stock_items, :shopify_inventory_level_id, unique: true,
              where: "shopify_inventory_level_id IS NOT NULL"

    # ─── Stock Movements (immutable audit trail) ────────────────────────────────
    create_table :stock_movements, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :stock_item, null: false, type: :uuid, foreign_key: true
      t.integer  :delta,         null: false   # positive = received, negative = fulfilled/adj
      t.string   :reason,        null: false   # "received", "fulfilled", "adjusted", "shopify_sync"
      t.string   :reference_type                # polymorphic: e.g. "DomainEvent"
      t.string   :reference_id
      t.integer  :snapshot_before,  null: false
      t.integer  :snapshot_after,   null: false
      t.timestamps
    end
  end
end
