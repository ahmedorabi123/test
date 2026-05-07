class AddStockReservationLifecycle < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    add_column :orders, :total_refunded, :decimal,
               precision: 12, scale: 2, default: 0, null: false unless column_exists?(:orders, :total_refunded)
    add_column :order_line_items, :fulfilled_quantity, :integer,
               default: 0, null: false unless column_exists?(:order_line_items, :fulfilled_quantity)
    add_column :stock_movements, :note, :string unless column_exists?(:stock_movements, :note)

    unless table_exists?(:stock_reservations)
      create_table :stock_reservations, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
        t.uuid    :order_line_item_id, null: false
        t.uuid    :stock_item_id,      null: false
        t.integer :quantity,           null: false
        t.string  :status,             null: false, default: "active"
        t.string  :note
        t.timestamps
      end
    end

    add_index :stock_reservations, %i[order_line_item_id stock_item_id],
              unique: true,
              where: "status = 'active'",
              name: "idx_stock_reservations_active_line_stock",
              algorithm: :concurrently unless index_exists?(:stock_reservations, %i[order_line_item_id stock_item_id], name: "idx_stock_reservations_active_line_stock")
    add_index :stock_reservations, %i[stock_item_id status],
              algorithm: :concurrently unless index_exists?(:stock_reservations, %i[stock_item_id status])
    add_index :stock_reservations, %i[order_line_item_id status],
              algorithm: :concurrently unless index_exists?(:stock_reservations, %i[order_line_item_id status])

    add_foreign_key :stock_reservations, :order_line_items,
                    on_delete: :cascade, validate: false unless foreign_key_exists?(:stock_reservations, :order_line_items)
    add_foreign_key :stock_reservations, :stock_items,
                    on_delete: :restrict, validate: false unless foreign_key_exists?(:stock_reservations, :stock_items)

    safety_assured do
      execute <<~SQL.squish
        UPDATE order_line_items
        SET fulfilled_quantity = COALESCE((
          SELECT SUM(fulfillment_line_items.quantity)
          FROM fulfillment_line_items
          INNER JOIN fulfillments ON fulfillments.id = fulfillment_line_items.fulfillment_id
          WHERE fulfillment_line_items.order_line_item_id = order_line_items.id
            AND fulfillments.status = 'success'
        ), 0)
      SQL

      execute <<~SQL.squish
        UPDATE orders
        SET total_refunded = COALESCE((
          SELECT SUM(refunds.amount)
          FROM refunds
          WHERE refunds.order_id = orders.id
        ), 0)
      SQL
    end

    validate_foreign_key :stock_reservations, :order_line_items if foreign_key_exists?(:stock_reservations, :order_line_items)
    validate_foreign_key :stock_reservations, :stock_items if foreign_key_exists?(:stock_reservations, :stock_items)
  end

  def down
    remove_foreign_key :stock_reservations, :stock_items if foreign_key_exists?(:stock_reservations, :stock_items)
    remove_foreign_key :stock_reservations, :order_line_items if foreign_key_exists?(:stock_reservations, :order_line_items)
    drop_table :stock_reservations if table_exists?(:stock_reservations)
    remove_column :stock_movements, :note if column_exists?(:stock_movements, :note)
    remove_column :order_line_items, :fulfilled_quantity if column_exists?(:order_line_items, :fulfilled_quantity)
    remove_column :orders, :total_refunded if column_exists?(:orders, :total_refunded)
  end
end