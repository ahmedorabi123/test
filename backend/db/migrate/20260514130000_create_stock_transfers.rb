class CreateStockTransfers < ActiveRecord::Migration[8.0]
  def change
    create_table :stock_transfers, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string :reference,        null: false
      t.uuid   :from_warehouse_id, null: false
      t.uuid   :to_warehouse_id,   null: false
      t.string :status,           null: false, default: "posted"
      t.string :reason,           null: false, default: "transfer"
      t.text   :note
      t.datetime :posted_at
      t.uuid   :posted_by_user_id
      t.uuid   :created_by_user_id

      t.timestamps
    end

    add_index :stock_transfers, :reference,           unique: true
    add_index :stock_transfers, :from_warehouse_id
    add_index :stock_transfers, :to_warehouse_id
    add_index :stock_transfers, :status
    add_index :stock_transfers, :posted_at

    safety_assured do
      add_foreign_key :stock_transfers, :warehouses, column: :from_warehouse_id
      add_foreign_key :stock_transfers, :warehouses, column: :to_warehouse_id
      add_foreign_key :stock_transfers, :users,      column: :posted_by_user_id
      add_foreign_key :stock_transfers, :users,      column: :created_by_user_id
    end
  end
end
