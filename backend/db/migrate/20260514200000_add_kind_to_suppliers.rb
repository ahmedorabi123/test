class AddKindToSuppliers < ActiveRecord::Migration[8.0]
  def up
    safety_assured do
      add_column :suppliers, :kind, :string, default: "factory", null: false
      add_index :suppliers, :kind
      add_check_constraint :suppliers, "kind IN ('factory','material')", name: "suppliers_kind_check"
    end
  end

  def down
    safety_assured do
      remove_check_constraint :suppliers, name: "suppliers_kind_check"
      remove_index :suppliers, :kind
      remove_column :suppliers, :kind
    end
  end
end
