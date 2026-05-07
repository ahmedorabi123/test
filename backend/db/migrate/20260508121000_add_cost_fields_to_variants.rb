class AddCostFieldsToVariants < ActiveRecord::Migration[8.0]
  def up
    add_column :variants, :cost, :decimal, precision: 12, scale: 2 unless column_exists?(:variants, :cost)
    add_column :variants, :last_purchase_cost, :decimal, precision: 12, scale: 2 unless column_exists?(:variants, :last_purchase_cost)

    safety_assured do
      execute <<~SQL.squish
        UPDATE variants
           SET cost = cost_per_item
         WHERE cost IS NULL
           AND cost_per_item IS NOT NULL
      SQL
    end
  end

  def down
    remove_column :variants, :last_purchase_cost if column_exists?(:variants, :last_purchase_cost)
    remove_column :variants, :cost if column_exists?(:variants, :cost)
  end
end
