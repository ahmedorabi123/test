class ChangeCurrencyDefaultsToEgp < ActiveRecord::Migration[8.0]
  TABLES = %w[
    suppliers
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
      change_column_default table, :currency, from: "USD", to: "EGP"
    end
  end

  def down
    TABLES.each do |table|
      next unless table_exists?(table)
      next unless column_exists?(table, :currency)
      change_column_default table, :currency, from: "EGP", to: "USD"
    end
  end
end
