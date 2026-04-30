class CreatePurchasesDomain < ActiveRecord::Migration[8.0]
  def change
    create_table :suppliers, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string   :name, null: false
      t.string   :email
      t.string   :phone
      t.jsonb    :address,     default: {}, null: false
      t.string   :tax_id
      t.string   :currency,    default: "USD", null: false
      t.jsonb    :payment_terms, default: {}, null: false
      t.string   :status,      default: "active", null: false
      t.text     :notes
      t.timestamps
    end
    add_index :suppliers, :name
    add_index :suppliers, :status

    create_table :purchase_orders, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string   :po_number,    null: false
      t.references :supplier,   type: :uuid, foreign_key: true, null: false
      t.references :warehouse,  type: :uuid, foreign_key: true, null: true
      t.string   :status,       default: "draft", null: false # draft, ordered, partial, received, cancelled
      t.string   :currency,     default: "USD", null: false
      t.decimal  :subtotal,     precision: 14, scale: 2, default: 0, null: false
      t.decimal  :total_tax,    precision: 14, scale: 2, default: 0, null: false
      t.decimal  :total_shipping, precision: 14, scale: 2, default: 0, null: false
      t.decimal  :total,        precision: 14, scale: 2, default: 0, null: false
      t.datetime :ordered_at
      t.datetime :expected_at
      t.datetime :received_at
      t.references :created_by, type: :uuid, foreign_key: { to_table: :users }, null: true
      t.text     :notes
      t.timestamps
    end
    add_index :purchase_orders, :po_number, unique: true
    add_index :purchase_orders, :status

    create_table :purchase_order_line_items, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :purchase_order, type: :uuid, foreign_key: true, null: false, index: { name: "idx_po_line_items_po" }
      t.references :variant,        type: :uuid, foreign_key: true, null: true
      t.string   :sku
      t.string   :title
      t.integer  :quantity_ordered,  default: 0, null: false
      t.integer  :quantity_received, default: 0, null: false
      t.decimal  :unit_cost,         precision: 14, scale: 2, default: 0, null: false
      t.decimal  :subtotal,          precision: 14, scale: 2, default: 0, null: false
      t.timestamps
    end
  end
end
