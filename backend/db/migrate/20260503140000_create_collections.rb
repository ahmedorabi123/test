class CreateCollections < ActiveRecord::Migration[8.0]
  def change
    create_table :collections, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.bigint   :shopify_collection_id
      t.string   :handle,          null: false
      t.string   :title,           null: false
      t.text     :body_html
      t.string   :image
      t.string   :sort_order,      default: "manual"
      t.datetime :published_at
      t.string   :published_scope, default: "web"
      t.string   :kind,            null: false, default: "custom"
      t.jsonb    :rules,           default: []
      t.boolean  :disjunctive,     default: false
      t.datetime :shopify_updated_at
      t.timestamps
    end

    add_index :collections, :shopify_collection_id, unique: true,
              where: "shopify_collection_id IS NOT NULL"
    add_index :collections, :handle, unique: true
    add_index :collections, :kind
  end
end
