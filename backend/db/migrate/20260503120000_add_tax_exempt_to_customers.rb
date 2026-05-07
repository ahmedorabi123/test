class AddTaxExemptToCustomers < ActiveRecord::Migration[8.0]
  def change
    add_column :customers, :tax_exempt, :boolean, default: false, null: false
  end
end
