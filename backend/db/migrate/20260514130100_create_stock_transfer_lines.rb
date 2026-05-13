class CreateStockTransferLines < ActiveRecord::Migration[8.0]
  def change
    create_table :stock_transfer_lines, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid    :stock_transfer_id, null: false
      t.uuid    :variant_id,        null: false
      t.integer :quantity,          null: false

      t.timestamps
    end

    add_index :stock_transfer_lines, :stock_transfer_id
    add_index :stock_transfer_lines, :variant_id
    add_index :stock_transfer_lines, %i[stock_transfer_id variant_id],
              unique: true,
              name: "idx_stock_transfer_lines_uniq_variant"

    safety_assured do
      add_foreign_key :stock_transfer_lines, :stock_transfers, on_delete: :cascade
      add_foreign_key :stock_transfer_lines, :variants

      add_check_constraint :stock_transfer_lines, "quantity > 0",
                           name: "stock_transfer_lines_quantity_positive"
    end
  end
end
