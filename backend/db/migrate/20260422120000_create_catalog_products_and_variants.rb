class CreateCatalogProductsAndVariants < ActiveRecord::Migration[8.0]
  def change
    create_table :products, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.string  :title,        null: false
      t.string  :handle,       null: false
      t.string  :status,       null: false, default: "active"   # active | draft | archived
      t.string  :vendor
      t.string  :product_type
      t.text    :description
      # Shopify linkage
      t.bigint  :shopify_product_id
      t.datetime :shopify_updated_at
      t.timestamps
    end

    add_index :products, :handle, unique: true
    add_index :products, :shopify_product_id, unique: true, where: "shopify_product_id IS NOT NULL"
    add_index :products, :status

    create_table :variants, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :product, type: :uuid, null: false, foreign_key: true
      t.string  :sku
      t.string  :title,        null: false, default: "Default Title"
      t.decimal :price,         precision: 12, scale: 2, null: false, default: 0
      t.decimal :compare_at_price, precision: 12, scale: 2
      t.string  :barcode
      t.integer :position, null: false, default: 1
      # Shopify linkage
      t.bigint  :shopify_variant_id
      t.bigint  :shopify_inventory_item_id
      t.timestamps
    end

    add_index :variants, :sku, unique: true, where: "sku IS NOT NULL AND sku <> ''"
    add_index :variants, :shopify_variant_id, unique: true, where: "shopify_variant_id IS NOT NULL"
    add_index :variants, :shopify_inventory_item_id
  end
end
