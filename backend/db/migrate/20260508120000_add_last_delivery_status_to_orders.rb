class AddLastDeliveryStatusToOrders < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    unless column_exists?(:orders, :last_delivery_status)
      add_column :orders, :last_delivery_status, :string
    end

    unless index_exists?(:orders, :last_delivery_status, name: "index_orders_on_last_delivery_status")
      add_index :orders, :last_delivery_status,
                algorithm: :concurrently,
                name: "index_orders_on_last_delivery_status"
    end

    # Backfill fulfillments.delivery_status: anything with delivered_at -> 'delivered',
    # otherwise default to 'pending' (covers manual fulfillments that never had it set).
    safety_assured do
      execute <<~SQL.squish
        UPDATE fulfillments
           SET delivery_status = 'delivered'
         WHERE delivery_status IS NULL
           AND delivered_at IS NOT NULL
      SQL
      execute <<~SQL.squish
        UPDATE fulfillments
           SET delivery_status = 'pending'
         WHERE delivery_status IS NULL
      SQL

      # Denormalise latest fulfillment's delivery_status onto orders.
      execute <<~SQL.squish
        UPDATE orders o
           SET last_delivery_status = f.delivery_status
          FROM (
            SELECT DISTINCT ON (order_id) order_id, delivery_status
              FROM fulfillments
             ORDER BY order_id, created_at DESC
          ) f
         WHERE f.order_id = o.id
      SQL
    end
  end

  def down
    if index_exists?(:orders, :last_delivery_status, name: "index_orders_on_last_delivery_status")
      remove_index :orders, name: "index_orders_on_last_delivery_status", algorithm: :concurrently
    end
    remove_column :orders, :last_delivery_status if column_exists?(:orders, :last_delivery_status)
  end
end
