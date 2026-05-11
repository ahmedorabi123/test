class AddCostBreakdownsToInventoryDocuments < ActiveRecord::Migration[8.0]
  def change
    add_column :fulfillment_line_items, :cost_breakdown, :jsonb, null: false, default: []
    add_column :refund_line_items, :cost_breakdown, :jsonb, null: false, default: []
  end
end