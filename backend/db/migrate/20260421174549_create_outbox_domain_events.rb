class CreateOutboxDomainEvents < ActiveRecord::Migration[8.0]
  def change
    create_table :domain_events, id: :uuid do |t|
      t.string   :aggregate_type,  null: false
      t.uuid     :aggregate_id,    null: false
      t.string   :event_type,      null: false
      t.jsonb    :payload,         null: false, default: {}
      t.datetime :occurred_at,     null: false
      t.datetime :dispatched_at
      t.timestamps
    end
    add_index :domain_events, %i[aggregate_type aggregate_id]
    add_index :domain_events, :event_type
    add_index :domain_events, :dispatched_at
  end
end
