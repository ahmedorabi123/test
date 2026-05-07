class AddSourceFieldsAndEgpCustomerDefault < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    change_column_default :customers, :currency, "EGP"

    add_column :customers, :source, :string, null: false, default: "manual" unless column_exists?(:customers, :source)
    add_column :products, :source, :string, null: false, default: "manual" unless column_exists?(:products, :source)
    add_column :collections, :source, :string, null: false, default: "manual" unless column_exists?(:collections, :source)

    add_index :customers, :source, algorithm: :concurrently unless index_exists?(:customers, :source)
    add_index :products, :source, algorithm: :concurrently unless index_exists?(:products, :source)
    add_index :collections, :source, algorithm: :concurrently unless index_exists?(:collections, :source)

    safety_assured do
        execute <<~SQL.squish
          UPDATE customers
          SET source = 'shopify'
          WHERE shopify_customer_id IS NOT NULL
        SQL

        execute <<~SQL.squish
          UPDATE products
          SET source = 'shopify'
          WHERE shopify_product_id IS NOT NULL
        SQL

        execute <<~SQL.squish
          UPDATE collections
          SET source = 'shopify'
          WHERE shopify_collection_id IS NOT NULL
        SQL
    end
  end

  def down
    remove_index :collections, :source, algorithm: :concurrently if index_exists?(:collections, :source)
    remove_index :products, :source, algorithm: :concurrently if index_exists?(:products, :source)
    remove_index :customers, :source, algorithm: :concurrently if index_exists?(:customers, :source)

    remove_column :collections, :source if column_exists?(:collections, :source)
    remove_column :products, :source if column_exists?(:products, :source)
    remove_column :customers, :source if column_exists?(:customers, :source)

    change_column_default :customers, :currency, "USD"
  end
end