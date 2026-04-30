class CreateRolesAndPermissions < ActiveRecord::Migration[8.0]
  def change
    create_table :roles, id: :uuid do |t|
      t.string :name,        null: false
      t.string :description
      t.timestamps
    end
    add_index :roles, :name, unique: true

    create_table :permissions, id: :uuid do |t|
      t.string :resource, null: false
      t.string :action,   null: false
      t.string :description
      t.timestamps
    end
    add_index :permissions, %i[resource action], unique: true

    create_table :role_permissions, id: :uuid do |t|
      t.references :role,       type: :uuid, null: false, foreign_key: true
      t.references :permission, type: :uuid, null: false, foreign_key: true
      t.timestamps
    end
    add_index :role_permissions, %i[role_id permission_id], unique: true

    create_table :user_roles, id: :uuid do |t|
      t.references :user, type: :uuid, null: false, foreign_key: true
      t.references :role, type: :uuid, null: false, foreign_key: true
      t.uuid :warehouse_id  # scope to showroom warehouse if set
      t.timestamps
    end
    add_index :user_roles, %i[user_id role_id warehouse_id], unique: true, name: "index_user_roles_unique"
  end
end
