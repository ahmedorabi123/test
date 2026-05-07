class AddShipmentEventsAndAnnotations < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    add_column :fulfillments, :notes, :text unless column_exists?(:fulfillments, :notes)
    add_column :fulfillments, :tags, :jsonb, default: [], null: false unless column_exists?(:fulfillments, :tags)
    add_column :fulfillments, :carrier_data, :jsonb, default: {}, null: false unless column_exists?(:fulfillments, :carrier_data)

    add_index :fulfillments, :tags, using: :gin, algorithm: :concurrently unless index_exists?(:fulfillments, :tags)
    add_index :fulfillments, :tracking_number, algorithm: :concurrently unless index_exists?(:fulfillments, :tracking_number)
    add_index :fulfillments, :delivery_status, algorithm: :concurrently unless index_exists?(:fulfillments, :delivery_status)
    add_index :fulfillments, :shipped_at, algorithm: :concurrently unless index_exists?(:fulfillments, :shipped_at)
    add_index :fulfillments, :delivered_at, algorithm: :concurrently unless index_exists?(:fulfillments, :delivered_at)

    unless table_exists?(:shipment_events)
      create_table :shipment_events, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
        t.uuid :fulfillment_id, null: false
        t.string :kind, null: false
        t.jsonb :payload, default: {}, null: false
        t.uuid :actor_id
        t.string :dedupe_key
        t.timestamps
      end
    end

    add_index :shipment_events, %i[fulfillment_id created_at], algorithm: :concurrently unless index_exists?(:shipment_events, %i[fulfillment_id created_at])
    add_index :shipment_events, :kind, algorithm: :concurrently unless index_exists?(:shipment_events, :kind)
    add_index :shipment_events, :dedupe_key, unique: true, where: "dedupe_key IS NOT NULL", algorithm: :concurrently unless index_exists?(:shipment_events, :dedupe_key)

    add_foreign_key :shipment_events, :fulfillments, on_delete: :cascade, validate: false unless foreign_key_exists?(:shipment_events, :fulfillments)
    add_foreign_key :shipment_events, :users, column: :actor_id, validate: false unless foreign_key_exists?(:shipment_events, :users, column: :actor_id)
    validate_foreign_key :shipment_events, :fulfillments if foreign_key_exists?(:shipment_events, :fulfillments)
    validate_foreign_key :shipment_events, :users if foreign_key_exists?(:shipment_events, :users, column: :actor_id)
  end

  def down
    remove_foreign_key :shipment_events, :users if foreign_key_exists?(:shipment_events, :users, column: :actor_id)
    remove_foreign_key :shipment_events, :fulfillments if foreign_key_exists?(:shipment_events, :fulfillments)
    drop_table :shipment_events if table_exists?(:shipment_events)

    remove_index :fulfillments, :delivered_at if index_exists?(:fulfillments, :delivered_at)
    remove_index :fulfillments, :shipped_at if index_exists?(:fulfillments, :shipped_at)
    remove_index :fulfillments, :delivery_status if index_exists?(:fulfillments, :delivery_status)
    remove_index :fulfillments, :tracking_number if index_exists?(:fulfillments, :tracking_number)
    remove_index :fulfillments, :tags if index_exists?(:fulfillments, :tags)
    remove_column :fulfillments, :carrier_data if column_exists?(:fulfillments, :carrier_data)
    remove_column :fulfillments, :tags if column_exists?(:fulfillments, :tags)
    remove_column :fulfillments, :notes if column_exists?(:fulfillments, :notes)
  end
end