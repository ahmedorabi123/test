class AddKindAndPartnerToWarehouses < ActiveRecord::Migration[8.0]
  def change
    add_column :warehouses, :kind,         :string, null: false, default: "own"
    add_column :warehouses, :partner_name, :string
  end
end
