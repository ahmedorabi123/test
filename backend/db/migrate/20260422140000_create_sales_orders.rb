class CreateSalesOrders < ActiveRecord::Migration[8.0]
  def change
    create_table :orders, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string  :order_number,        null: false           # internal, e.g. "SO-2026-0001"
      t.string  :external_number                            # Shopify "name" like "#1001"
      t.string  :source,              null: false, default: "manual" # manual | shopify | showroom
      t.string  :status,              null: false, default: "pending"
      # pending | processing | fulfilled | cancelled | refunded
      t.string  :financial_status,    null: false, default: "pending"
      # pending | authorized | paid | partially_paid | refunded | voided
      t.string  :fulfillment_status                         # null | partial | fulfilled
      t.string  :currency,            null: false, default: "USD"

      t.decimal :subtotal_price,      precision: 12, scale: 2, null: false, default: 0
      t.decimal :total_tax,           precision: 12, scale: 2, null: false, default: 0
      t.decimal :total_shipping,      precision: 12, scale: 2, null: false, default: 0
      t.decimal :total_discount,      precision: 12, scale: 2, null: false, default: 0
      t.decimal :total_price,         precision: 12, scale: 2, null: false, default: 0

      t.string  :customer_email
      t.string  :customer_name
      t.jsonb   :shipping_address,    null: false, default: {}
      t.jsonb   :billing_address,     null: false, default: {}

      t.text    :notes
      t.datetime :placed_at,          null: false
      t.datetime :cancelled_at

      # Shopify linkage
      t.bigint   :shopify_order_id
      t.datetime :shopify_updated_at

      t.timestamps
    end

    add_index :orders, :order_number, unique: true
    add_index :orders, :shopify_order_id, unique: true, where: "shopify_order_id IS NOT NULL"
    add_index :orders, :status
    add_index :orders, :financial_status
    add_index :orders, :placed_at
    add_index :orders, :customer_email

    create_table :order_line_items, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :order,    null: false, type: :uuid, foreign_key: true
      t.references :variant,  null: true,  type: :uuid, foreign_key: true
      t.string  :sku
      t.string  :title,              null: false
      t.string  :variant_title
      t.integer :quantity,           null: false, default: 1
      t.decimal :price,              precision: 12, scale: 2, null: false, default: 0
      t.decimal :total_discount,     precision: 12, scale: 2, null: false, default: 0
      t.decimal :total_tax,          precision: 12, scale: 2, null: false, default: 0
      t.decimal :line_total,         precision: 12, scale: 2, null: false, default: 0

      t.bigint  :shopify_line_item_id
      t.timestamps
    end

    add_index :order_line_items, :shopify_line_item_id, unique: true,
              where: "shopify_line_item_id IS NOT NULL"
    add_index :order_line_items, :sku
  end
end
