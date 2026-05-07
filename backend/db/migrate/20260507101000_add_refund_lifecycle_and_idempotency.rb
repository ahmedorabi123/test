class AddRefundLifecycleAndIdempotency < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    add_column :refunds, :status, :string, default: "processed", null: false unless column_exists?(:refunds, :status)
    add_column :refunds, :kind, :string, default: "manual", null: false unless column_exists?(:refunds, :kind)
    add_column :refunds, :idempotency_key, :string unless column_exists?(:refunds, :idempotency_key)
    add_column :refunds, :content_hash, :string unless column_exists?(:refunds, :content_hash)

    safety_assured do
      execute "UPDATE refunds SET status = 'processed' WHERE status IS NULL OR status = ''"
      execute <<~SQL.squish
        UPDATE refunds
        SET kind = CASE
          WHEN shopify_refund_id IS NOT NULL THEN 'shopify'
          WHEN LOWER(COALESCE(reason, '')) = 'estebdal' THEN 'estebdal'
          ELSE 'manual'
        END
      SQL
    end

    add_index :refunds, :status, algorithm: :concurrently unless index_exists?(:refunds, :status)
    add_index :refunds, :kind, algorithm: :concurrently unless index_exists?(:refunds, :kind)
    add_index :refunds, :processed_at, algorithm: :concurrently unless index_exists?(:refunds, :processed_at)
    add_index :refunds, :content_hash, algorithm: :concurrently unless index_exists?(:refunds, :content_hash)
    add_index :refunds, :idempotency_key, unique: true, where: "idempotency_key IS NOT NULL", algorithm: :concurrently unless index_exists?(:refunds, :idempotency_key)
    add_index :refund_line_items, %i[refund_id shopify_line_item_id], unique: true, where: "shopify_line_item_id IS NOT NULL", name: "idx_refund_line_items_refund_shopify_line", algorithm: :concurrently unless index_exists?(:refund_line_items, %i[refund_id shopify_line_item_id], name: "idx_refund_line_items_refund_shopify_line")
  end

  def down
    remove_index :refund_line_items, name: "idx_refund_line_items_refund_shopify_line" if index_exists?(:refund_line_items, name: "idx_refund_line_items_refund_shopify_line")
    remove_index :refunds, :idempotency_key if index_exists?(:refunds, :idempotency_key)
    remove_index :refunds, :content_hash if index_exists?(:refunds, :content_hash)
    remove_index :refunds, :processed_at if index_exists?(:refunds, :processed_at)
    remove_index :refunds, :kind if index_exists?(:refunds, :kind)
    remove_index :refunds, :status if index_exists?(:refunds, :status)
    remove_column :refunds, :content_hash if column_exists?(:refunds, :content_hash)
    remove_column :refunds, :idempotency_key if column_exists?(:refunds, :idempotency_key)
    remove_column :refunds, :kind if column_exists?(:refunds, :kind)
    remove_column :refunds, :status if column_exists?(:refunds, :status)
  end
end