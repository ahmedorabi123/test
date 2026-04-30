class AddShopifyParityFields < ActiveRecord::Migration[8.0]
  def change
    safety_assured do
    # ── Orders ──────────────────────────────────────────────────────────────
    change_table :orders, bulk: true do |t|
      t.jsonb  :tags,                     default: [], null: false
      t.string :delivery_method
      t.integer :items_count,             default: 0,  null: false
      t.jsonb  :payment_gateway_names,    default: [], null: false
      t.string :risk_level
      t.string :cancel_reason
      t.datetime :closed_at
      t.decimal :total_outstanding, precision: 12, scale: 2, default: "0.0", null: false
      t.string :shopify_order_status_url
    end
    add_index :orders, :tags, using: :gin

    # ── Fulfillments ────────────────────────────────────────────────────────
    change_table :fulfillments, bulk: true do |t|
      t.string :delivery_status   # in_transit / out_for_delivery / delivered / failure / etc.
      t.string :service           # bosta / aramex / manual
    end

    # ── Refunds ─────────────────────────────────────────────────────────────
    change_table :refunds, bulk: true do |t|
      t.jsonb :transactions, default: [], null: false
    end

    # ── Customers ───────────────────────────────────────────────────────────
    change_table :customers, bulk: true do |t|
      t.boolean :accepts_marketing, default: false, null: false
      t.boolean :verified_email,    default: false, null: false
      t.string  :state                                # enabled / disabled / invited / declined
      t.jsonb   :addresses, default: [], null: false  # full list, beyond default_address
      t.text    :note
      t.bigint  :last_order_id                        # shopify order id (bigint)
      t.string  :last_order_name
      t.datetime :last_order_at
    end

    # ── Products: optional metafields blob ──────────────────────────────────
    change_table :products, bulk: true do |t|
      t.jsonb :metafields, default: [], null: false
    end
    end
  end
end
