class CreateStockCostLayers < ActiveRecord::Migration[8.0]
  def change
    create_table :stock_cost_layers, id: :uuid do |t|
      t.references :stock_item, null: false, type: :uuid, foreign_key: true
      t.references :variant, null: false, type: :uuid, foreign_key: true
      t.references :warehouse, null: false, type: :uuid, foreign_key: true
      t.datetime :received_at, null: false
      t.integer :quantity_received, null: false
      t.integer :qty_remaining, null: false
      t.decimal :unit_cost, precision: 15, scale: 4, null: false, default: 0
      t.string :source_type, null: false
      t.string :source_id, null: false
      t.jsonb :details, null: false, default: {}
      t.timestamps
    end

    add_index :stock_cost_layers, %i[stock_item_id received_at created_at]
    add_index :stock_cost_layers, %i[variant_id warehouse_id received_at]
    add_index :stock_cost_layers, %i[source_type source_id]
    add_check_constraint :stock_cost_layers, "quantity_received > 0", name: "stock_cost_layers_quantity_received_positive"
    add_check_constraint :stock_cost_layers, "qty_remaining >= 0", name: "stock_cost_layers_qty_remaining_non_negative"
    add_check_constraint :stock_cost_layers, "unit_cost >= 0", name: "stock_cost_layers_unit_cost_non_negative"
  end
end