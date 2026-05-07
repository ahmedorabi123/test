class AddPhase8LifecycleIndexes < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    unless index_exists?(:fulfillments, %i[order_id created_at], name: "idx_fulfillments_order_created_at_desc")
      add_index :fulfillments, %i[order_id created_at],
                order: { created_at: :desc },
                algorithm: :concurrently,
                name: "idx_fulfillments_order_created_at_desc"
    end

    unless index_exists?(:refunds, %i[order_id processed_at], name: "idx_refunds_order_processed_at_desc")
      add_index :refunds, %i[order_id processed_at],
                order: { processed_at: :desc },
                algorithm: :concurrently,
                name: "idx_refunds_order_processed_at_desc"
    end

    unless index_exists?(:purchase_order_line_items, %i[variant_id created_at], name: "idx_po_line_items_variant_created_at_desc")
      add_index :purchase_order_line_items, %i[variant_id created_at],
                order: { created_at: :desc },
                algorithm: :concurrently,
                name: "idx_po_line_items_variant_created_at_desc"
    end
  end

  def down
    if index_exists?(:purchase_order_line_items, name: "idx_po_line_items_variant_created_at_desc")
      remove_index :purchase_order_line_items, name: "idx_po_line_items_variant_created_at_desc", algorithm: :concurrently
    end
    if index_exists?(:refunds, name: "idx_refunds_order_processed_at_desc")
      remove_index :refunds, name: "idx_refunds_order_processed_at_desc", algorithm: :concurrently
    end
    if index_exists?(:fulfillments, name: "idx_fulfillments_order_created_at_desc")
      remove_index :fulfillments, name: "idx_fulfillments_order_created_at_desc", algorithm: :concurrently
    end
  end
end
