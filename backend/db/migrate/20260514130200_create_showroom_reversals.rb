class CreateShowroomReversals < ActiveRecord::Migration[8.0]
  def change
    create_table :showroom_reversals, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid    :warehouse_id,    null: false
      t.string  :period,          null: false
      t.string  :currency,        null: false, limit: 3, default: "EGP"
      t.decimal :total_amount,    precision: 14, scale: 2, null: false, default: "0.0"
      t.jsonb   :lines,           null: false, default: []
      t.string  :idempotency_key, null: false
      t.text    :notes
      t.uuid    :posted_by_user_id
      t.datetime :posted_at

      t.timestamps
    end

    add_index :showroom_reversals, :idempotency_key, unique: true
    add_index :showroom_reversals, %i[warehouse_id period], unique: true,
              name: "idx_showroom_reversals_uniq_warehouse_period"
    add_index :showroom_reversals, :period
    safety_assured do
      add_foreign_key :showroom_reversals, :warehouses
      add_foreign_key :showroom_reversals, :users, column: :posted_by_user_id
    end
  end
end
