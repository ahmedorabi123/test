class AddQuantityUnavailableToStockItems < ActiveRecord::Migration[8.0]
  def change
    add_column :stock_items, :quantity_unavailable, :integer, default: 0, null: false
    add_column :stock_items, :unavailability_reason, :string
  end
end
