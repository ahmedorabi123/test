class CreateManufacturingDomain < ActiveRecord::Migration[8.0]
  def change
    create_table :production_orders, id: :uuid do |t|
      t.string     :number,           null: false
      t.references :parent_variant,   type: :uuid, null: false,
                                      foreign_key: { to_table: :variants }
      t.references :warehouse,        type: :uuid, null: false,
                                      foreign_key: true
      t.integer    :quantity,         null: false
      t.string     :status,           null: false, default: "draft"
      t.references :created_by,       type: :uuid,
                                      foreign_key: { to_table: :users }
      t.string     :notes
      t.datetime   :started_at
      t.datetime   :completed_at
      t.datetime   :cancelled_at

      t.timestamps
    end

    add_index :production_orders, :number,  unique: true
    add_index :production_orders, :status
  end
end
