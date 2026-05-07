class MigrateUsdCurrencyToEgp < ActiveRecord::Migration[8.0]
  TABLES = %w[
    orders
    customers
    refunds
    journal_entries
    purchase_orders
    warehouses
    showroom_sales_reports
  ].freeze

  def up
    TABLES.each do |table|
      next unless table_exists?(table)
      next unless column_exists?(table, :currency)
      safety_assured { execute "UPDATE #{table} SET currency = 'EGP' WHERE currency = 'USD'" }
    end
  end

  def down
    TABLES.each do |table|
      next unless table_exists?(table)
      next unless column_exists?(table, :currency)
      safety_assured { execute "UPDATE #{table} SET currency = 'EGP' WHERE currency = 'USD'" }
    end
  end
end
