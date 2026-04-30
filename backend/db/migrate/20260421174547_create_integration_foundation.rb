class CreateIntegrationFoundation < ActiveRecord::Migration[8.0]
  def change
    # Idempotency store for incoming webhooks
    create_table :webhook_events, id: :uuid do |t|
      t.string   :source,       null: false  # "shopify"
      t.string   :topic,        null: false  # "orders/create"
      t.string   :external_id,  null: false  # X-Shopify-Webhook-Id
      t.jsonb    :payload,      null: false, default: {}
      t.datetime :received_at,  null: false
      t.datetime :processed_at
      t.text     :error
      t.integer  :attempts,     null: false, default: 0
      t.timestamps
    end
    add_index :webhook_events, %i[source external_id], unique: true, name: "index_webhook_events_on_source_external_id"
    add_index :webhook_events, :topic
    add_index :webhook_events, :processed_at

    # Track last sync cursor per resource
    create_table :sync_cursors, id: :uuid do |t|
      t.string   :source,        null: false
      t.string   :resource,      null: false
      t.string   :last_cursor
      t.datetime :last_synced_at
      t.timestamps
    end
    add_index :sync_cursors, %i[source resource], unique: true

    # Bidirectional Shopify <-> local ID mapping
    create_table :shopify_mappings, id: :uuid do |t|
      t.string :local_type,   null: false
      t.uuid   :local_id,     null: false
      t.string :shopify_type, null: false
      t.string :shopify_gid,  null: false
      t.timestamps
    end
    add_index :shopify_mappings, :shopify_gid, unique: true
    add_index :shopify_mappings, %i[local_type local_id], name: "index_shopify_mappings_on_local"
  end
end
