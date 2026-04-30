class CreateBomItems < ActiveRecord::Migration[8.0]
  def change
    create_table :bom_items, id: :uuid do |t|
      t.references :parent_variant,    type: :uuid, null: false,
                   foreign_key: { to_table: :variants }
      t.references :component_variant, type: :uuid, null: false,
                   foreign_key: { to_table: :variants }
      t.decimal :quantity,     precision: 14, scale: 4, null: false, default: 1
      t.decimal :waste_factor, precision: 6,  scale: 4, null: false, default: 0

      t.timestamps
    end

    add_index :bom_items,
              %i[parent_variant_id component_variant_id],
              unique: true,
              name: "idx_bom_items_parent_component_uniq"
  end
end
