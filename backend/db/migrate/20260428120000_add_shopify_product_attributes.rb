class AddShopifyProductAttributes < ActiveRecord::Migration[8.0]
  disable_ddl_transaction!

  def change
    # ── Products: full Shopify-parity attributes ──
    safety_assured do
      change_table :products do |t|
        t.jsonb    :tags,             default: [], null: false
        t.string   :seo_title
        t.text     :seo_description
        t.string   :template_suffix
        t.datetime :published_at
        t.string   :published_scope, default: "web", null: false
        t.boolean  :gift_card,       default: false, null: false
      end
    end
    add_index :products, :tags, using: :gin, algorithm: :concurrently

    # ── Variants: full Shopify-parity attributes ──
    safety_assured do
      change_table :variants do |t|
        t.string  :option1
        t.string  :option2
        t.string  :option3
        t.decimal :weight,  precision: 10, scale: 3
        t.string  :weight_unit,         default: "kg",      null: false
        t.string  :inventory_policy,    default: "deny",    null: false
        t.string  :inventory_management
        t.boolean :requires_shipping,   default: true,      null: false
        t.boolean :taxable,             default: true,      null: false
        t.string  :fulfillment_service, default: "manual",  null: false
        t.string  :hs_code
        t.string  :country_of_origin
        t.decimal :cost_per_item, precision: 12, scale: 2
      end
    end

    # ── Product options (Shopify "Size", "Color" structure) ──
    create_table :product_options, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :product, type: :uuid, null: false, foreign_key: true
      t.string  :name,     null: false
      t.integer :position, default: 1, null: false
      t.timestamps
    end
    add_index :product_options, [:product_id, :name], unique: true

    # ── Product option values (the value choices for each option) ──
    create_table :product_option_values, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :product_option, type: :uuid, null: false, foreign_key: true
      t.string  :value,    null: false
      t.integer :position, default: 1, null: false
      t.timestamps
    end
    add_index :product_option_values, [:product_option_id, :value], unique: true,
              name: "idx_product_option_values_unique"

    # ── Product images ──
    create_table :product_images, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :product, type: :uuid, null: false, foreign_key: true
      t.references :variant, type: :uuid, foreign_key: true
      t.text    :src,      null: false
      t.string  :alt
      t.integer :position, default: 1, null: false
      t.integer :width
      t.integer :height
      t.bigint  :shopify_image_id
      t.timestamps
    end
    add_index :product_images, :shopify_image_id, unique: true,
              where: "shopify_image_id IS NOT NULL"
  end
end
