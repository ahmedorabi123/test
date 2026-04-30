class CreateCrmShippingAndRefunds < ActiveRecord::Migration[8.0]
  def change
    # ── CRM — Customers ──────────────────────────────────────────────────────
    create_table :customers, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string  :email
      t.string  :phone
      t.string  :first_name
      t.string  :last_name
      t.jsonb   :tags,            default: [], null: false
      t.jsonb   :default_address, default: {}, null: false
      t.integer :orders_count,    default: 0,  null: false
      t.decimal :total_spent,     precision: 14, scale: 2, default: 0, null: false
      t.string  :currency,        default: "USD", null: false
      t.string  :shopify_customer_id
      t.datetime :shopify_updated_at
      t.timestamps
    end
    add_index :customers, :email
    add_index :customers, :phone
    add_index :customers, :shopify_customer_id, unique: true, where: "shopify_customer_id IS NOT NULL"

    # ── Link orders to customers + location_id for fulfillment allocation ────
    # NOTE: avoid change_table — strong_migrations cannot inspect its block and
    # raises even inside safety_assured (SM 2.x known limitation). Use
    # individual add_column / add_index / add_foreign_key instead.
    add_column :orders, :customer_id,         :uuid
    add_column :orders, :shopify_customer_id, :bigint
    add_column :orders, :location_id,         :bigint
    safety_assured do
      add_index       :orders, :customer_id
      add_foreign_key :orders, :customers, column: :customer_id, validate: false
      add_index       :orders, :shopify_customer_id,
                      where: "shopify_customer_id IS NOT NULL"
    end

    # ── Warehouses ← map to Shopify locations ────────────────────────────────
    safety_assured do
      add_column :warehouses, :shopify_location_id, :bigint
      add_index  :warehouses, :shopify_location_id, unique: true, where: "shopify_location_id IS NOT NULL"
    end

    # ── Shipping — Fulfillments ──────────────────────────────────────────────
    create_table :fulfillments, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :order, type: :uuid, foreign_key: true, null: false, index: true
      t.bigint   :shopify_fulfillment_id
      t.bigint   :location_id
      t.string   :status,           default: "success", null: false
      t.string   :tracking_company
      t.string   :tracking_number
      t.string   :tracking_url
      t.datetime :shipped_at
      t.datetime :delivered_at
      t.datetime :shopify_updated_at
      t.timestamps
    end
    add_index :fulfillments, :shopify_fulfillment_id, unique: true, where: "shopify_fulfillment_id IS NOT NULL"

    create_table :fulfillment_line_items, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :fulfillment,     type: :uuid, foreign_key: true, null: false, index: true
      t.references :order_line_item, type: :uuid, foreign_key: true, null: true
      t.bigint   :shopify_line_item_id
      t.integer  :quantity, null: false, default: 0
      t.timestamps
    end

    # ── Returns / Refunds (Estebdal) ─────────────────────────────────────────
    create_table :refunds, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :order, type: :uuid, foreign_key: true, null: false, index: true
      t.bigint   :shopify_refund_id
      t.decimal  :amount, precision: 14, scale: 2, default: 0, null: false
      t.string   :currency, default: "USD", null: false
      t.string   :reason
      t.text     :note
      t.boolean  :restock,   default: false, null: false
      t.boolean  :inventory_restocked, default: false, null: false
      t.datetime :processed_at
      t.datetime :shopify_updated_at
      t.timestamps
    end
    add_index :refunds, :shopify_refund_id, unique: true, where: "shopify_refund_id IS NOT NULL"

    create_table :refund_line_items, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :refund,          type: :uuid, foreign_key: true, null: false, index: true
      t.references :order_line_item, type: :uuid, foreign_key: true, null: true
      t.bigint   :shopify_line_item_id
      t.integer  :quantity, default: 0, null: false
      t.decimal  :subtotal, precision: 14, scale: 2, default: 0, null: false
      t.boolean  :restock,  default: false, null: false
      t.string   :restock_type # "return" | "cancel" | "no_restock"
      t.bigint   :location_id
      t.timestamps
    end
  end
end
