class CreateCollectionProducts < ActiveRecord::Migration[8.0]
  def change
    create_table :collection_products, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.uuid    :collection_id, null: false
      t.uuid    :product_id,    null: false
      t.integer :position,      default: 0, null: false
      t.timestamps
    end

    add_index :collection_products, [:collection_id, :product_id], unique: true
    add_index :collection_products, :product_id

    add_foreign_key :collection_products, :collections, on_delete: :cascade, validate: false
    add_foreign_key :collection_products, :products,    on_delete: :cascade, validate: false
  end
end
