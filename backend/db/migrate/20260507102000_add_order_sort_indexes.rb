class AddOrderSortIndexes < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    add_index :orders, :created_at, algorithm: :concurrently unless index_exists?(:orders, :created_at)
    add_index :orders, :updated_at, algorithm: :concurrently unless index_exists?(:orders, :updated_at)
    add_index :orders, :total_price, algorithm: :concurrently unless index_exists?(:orders, :total_price)
    add_index :orders, :fulfillment_status, algorithm: :concurrently unless index_exists?(:orders, :fulfillment_status)
    add_index :orders, :customer_name, algorithm: :concurrently unless index_exists?(:orders, :customer_name)
    add_index :orders, :items_count, algorithm: :concurrently unless index_exists?(:orders, :items_count)
    add_index :orders, :total_refunded, algorithm: :concurrently if column_exists?(:orders, :total_refunded) && !index_exists?(:orders, :total_refunded)
  end
end