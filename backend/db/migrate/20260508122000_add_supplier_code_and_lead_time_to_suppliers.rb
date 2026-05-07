class AddSupplierCodeAndLeadTimeToSuppliers < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def up
    add_column :suppliers, :supplier_code, :string unless column_exists?(:suppliers, :supplier_code)
    add_column :suppliers, :lead_time_days, :integer unless column_exists?(:suppliers, :lead_time_days)

    unless index_exists?(:suppliers, :supplier_code, name: "index_suppliers_on_supplier_code")
      add_index :suppliers, :supplier_code,
                unique: true,
                where: "supplier_code IS NOT NULL",
                algorithm: :concurrently,
                name: "index_suppliers_on_supplier_code"
    end
  end

  def down
    if index_exists?(:suppliers, :supplier_code, name: "index_suppliers_on_supplier_code")
      remove_index :suppliers, name: "index_suppliers_on_supplier_code", algorithm: :concurrently
    end
    remove_column :suppliers, :lead_time_days if column_exists?(:suppliers, :lead_time_days)
    remove_column :suppliers, :supplier_code if column_exists?(:suppliers, :supplier_code)
  end
end
