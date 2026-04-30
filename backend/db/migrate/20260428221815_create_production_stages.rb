class CreateProductionStages < ActiveRecord::Migration[8.0]
  def change
    create_table :production_stages, id: :uuid do |t|
      t.references :production_order, type: :uuid, null: false,
                   foreign_key: true, index: true
      t.integer    :position,    null: false, default: 0
      t.string     :name,        null: false                # e.g. "Cutting", "Sewing", "Printing", "QC"
      t.string     :status,      null: false, default: "pending"
                                                            # pending, in_progress, completed, skipped
      t.references :supplier,    type: :uuid, foreign_key: true
                                                            # the factory / sub-contractor handling this stage
      t.decimal    :unit_cost,   precision: 14, scale: 4, default: 0
      t.string     :cost_currency, default: "USD"
      t.datetime   :started_at
      t.datetime   :completed_at
      t.string     :notes
      t.timestamps
    end

    add_index :production_stages, %i[production_order_id position], unique: true,
              name: "idx_production_stages_order_position_uniq"
    add_index :production_stages, :status

    safety_assured do
      change_table :production_orders, bulk: true do |t|
        t.string  :production_mode, null: false, default: "single"
                                                            # single | staged
        t.decimal :unit_cost,       precision: 14, scale: 4, default: 0
        t.string  :cost_currency,   default: "USD"
      end
    end
  end
end
