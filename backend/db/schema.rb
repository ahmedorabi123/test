# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2026_05_11_220518) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"

  create_table "accounts", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "code", null: false
    t.string "name", null: false
    t.string "account_type", null: false
    t.string "normal_side", null: false
    t.text "description"
    t.boolean "active", default: true, null: false
    t.string "currency", default: "EGP", null: false
    t.uuid "parent_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_type"], name: "index_accounts_on_account_type"
    t.index ["code"], name: "index_accounts_on_code", unique: true
    t.index ["parent_id"], name: "index_accounts_on_parent_id"
  end

  create_table "active_storage_attachments", force: :cascade do |t|
    t.string "name", null: false
    t.string "record_type", null: false
    t.bigint "record_id", null: false
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.string "key", null: false
    t.string "filename", null: false
    t.string "content_type"
    t.text "metadata"
    t.string "service_name", null: false
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.datetime "created_at", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "audit_logs", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id"
    t.string "action", null: false
    t.string "subject_type", null: false
    t.uuid "subject_id"
    t.jsonb "diff", default: {}
    t.string "ip_address"
    t.string "user_agent"
    t.datetime "occurred_at", default: -> { "now()" }, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["occurred_at"], name: "index_audit_logs_on_occurred_at"
    t.index ["subject_type", "subject_id"], name: "index_audit_logs_on_subject_type_and_subject_id"
    t.index ["user_id"], name: "index_audit_logs_on_user_id"
  end

  create_table "bom_items", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "parent_variant_id", null: false
    t.uuid "component_variant_id", null: false
    t.decimal "quantity", precision: 14, scale: 4, default: "1.0", null: false
    t.decimal "waste_factor", precision: 6, scale: 4, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["component_variant_id"], name: "index_bom_items_on_component_variant_id"
    t.index ["parent_variant_id", "component_variant_id"], name: "idx_bom_items_parent_component_uniq", unique: true
    t.index ["parent_variant_id"], name: "index_bom_items_on_parent_variant_id"
  end

  create_table "collection_products", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "collection_id", null: false
    t.uuid "product_id", null: false
    t.integer "position", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["collection_id", "product_id"], name: "index_collection_products_on_collection_id_and_product_id", unique: true
    t.index ["product_id"], name: "index_collection_products_on_product_id"
  end

  create_table "collections", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.bigint "shopify_collection_id"
    t.string "handle", null: false
    t.string "title", null: false
    t.text "body_html"
    t.string "image"
    t.string "sort_order", default: "manual"
    t.datetime "published_at"
    t.string "published_scope", default: "web"
    t.string "kind", default: "custom", null: false
    t.jsonb "rules", default: []
    t.boolean "disjunctive", default: false
    t.datetime "shopify_updated_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "source", default: "manual", null: false
    t.index ["handle"], name: "index_collections_on_handle", unique: true
    t.index ["kind"], name: "index_collections_on_kind"
    t.index ["shopify_collection_id"], name: "index_collections_on_shopify_collection_id", unique: true, where: "(shopify_collection_id IS NOT NULL)"
    t.index ["source"], name: "index_collections_on_source"
  end

  create_table "customers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "email"
    t.string "phone"
    t.string "first_name"
    t.string "last_name"
    t.jsonb "tags", default: [], null: false
    t.jsonb "default_address", default: {}, null: false
    t.integer "orders_count", default: 0, null: false
    t.decimal "total_spent", precision: 14, scale: 2, default: "0.0", null: false
    t.string "currency", default: "EGP", null: false
    t.string "shopify_customer_id"
    t.datetime "shopify_updated_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.boolean "accepts_marketing", default: false, null: false
    t.boolean "verified_email", default: false, null: false
    t.string "state"
    t.jsonb "addresses", default: [], null: false
    t.text "note"
    t.bigint "last_order_id"
    t.string "last_order_name"
    t.datetime "last_order_at"
    t.boolean "tax_exempt", default: false, null: false
    t.string "source", default: "manual", null: false
    t.index ["email"], name: "index_customers_on_email"
    t.index ["phone"], name: "index_customers_on_phone"
    t.index ["shopify_customer_id"], name: "index_customers_on_shopify_customer_id", unique: true, where: "(shopify_customer_id IS NOT NULL)"
    t.index ["source"], name: "index_customers_on_source"
  end

  create_table "domain_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "aggregate_type", null: false
    t.string "aggregate_id", null: false
    t.string "event_type", null: false
    t.jsonb "payload", default: {}, null: false
    t.datetime "occurred_at", null: false
    t.datetime "dispatched_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["aggregate_type", "aggregate_id"], name: "index_domain_events_on_aggregate_type_and_aggregate_id"
    t.index ["dispatched_at"], name: "index_domain_events_on_dispatched_at"
    t.index ["event_type"], name: "index_domain_events_on_event_type"
  end

  create_table "fulfillment_line_items", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "fulfillment_id", null: false
    t.uuid "order_line_item_id"
    t.bigint "shopify_line_item_id"
    t.integer "quantity", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["fulfillment_id"], name: "index_fulfillment_line_items_on_fulfillment_id"
    t.index ["order_line_item_id"], name: "index_fulfillment_line_items_on_order_line_item_id"
  end

  create_table "fulfillments", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "order_id", null: false
    t.bigint "shopify_fulfillment_id"
    t.bigint "location_id"
    t.string "status", default: "success", null: false
    t.string "tracking_company"
    t.string "tracking_number"
    t.string "tracking_url"
    t.datetime "shipped_at"
    t.datetime "delivered_at"
    t.datetime "shopify_updated_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "delivery_status"
    t.string "service"
    t.text "notes"
    t.jsonb "tags", default: [], null: false
    t.jsonb "carrier_data", default: {}, null: false
    t.datetime "in_transit_at"
    t.index ["delivered_at"], name: "index_fulfillments_on_delivered_at"
    t.index ["delivery_status"], name: "index_fulfillments_on_delivery_status"
    t.index ["order_id", "created_at"], name: "idx_fulfillments_order_created_at_desc", order: { created_at: :desc }
    t.index ["order_id"], name: "index_fulfillments_on_order_id"
    t.index ["shipped_at"], name: "index_fulfillments_on_shipped_at"
    t.index ["shopify_fulfillment_id"], name: "index_fulfillments_on_shopify_fulfillment_id", unique: true, where: "(shopify_fulfillment_id IS NOT NULL)"
    t.index ["tags"], name: "index_fulfillments_on_tags", using: :gin
    t.index ["tracking_number"], name: "index_fulfillments_on_tracking_number"
  end

  create_table "journal_entries", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.date "entry_date", null: false
    t.string "description", null: false
    t.string "status", default: "posted", null: false
    t.string "currency", default: "EGP", null: false
    t.string "source_type"
    t.string "source_id"
    t.string "entry_type"
    t.string "idempotency_key"
    t.uuid "reversal_of_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["entry_date"], name: "index_journal_entries_on_entry_date"
    t.index ["idempotency_key"], name: "index_journal_entries_on_idempotency_key", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["reversal_of_id"], name: "index_journal_entries_on_reversal_of_id"
    t.index ["source_type", "source_id"], name: "index_journal_entries_on_source_type_and_source_id"
    t.index ["status"], name: "index_journal_entries_on_status"
  end

  create_table "journal_lines", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "journal_entry_id", null: false
    t.uuid "account_id", null: false
    t.string "side", null: false
    t.decimal "amount", precision: 15, scale: 2, null: false
    t.string "currency", default: "EGP", null: false
    t.text "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["account_id", "side"], name: "index_journal_lines_on_account_id_and_side"
    t.index ["account_id"], name: "index_journal_lines_on_account_id"
    t.index ["journal_entry_id"], name: "index_journal_lines_on_journal_entry_id"
    t.index ["side"], name: "index_journal_lines_on_side"
  end

  create_table "order_line_items", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "order_id", null: false
    t.uuid "variant_id"
    t.string "sku"
    t.string "title", null: false
    t.string "variant_title"
    t.integer "quantity", default: 1, null: false
    t.decimal "price", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "total_discount", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "total_tax", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "line_total", precision: 12, scale: 2, default: "0.0", null: false
    t.bigint "shopify_line_item_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "fulfilled_quantity", default: 0, null: false
    t.index ["order_id"], name: "index_order_line_items_on_order_id"
    t.index ["shopify_line_item_id"], name: "index_order_line_items_on_shopify_line_item_id", unique: true, where: "(shopify_line_item_id IS NOT NULL)"
    t.index ["sku"], name: "index_order_line_items_on_sku"
    t.index ["variant_id"], name: "index_order_line_items_on_variant_id"
  end

  create_table "orders", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "order_number", null: false
    t.string "external_number"
    t.string "source", default: "manual", null: false
    t.string "status", default: "pending", null: false
    t.string "financial_status", default: "pending", null: false
    t.string "fulfillment_status"
    t.string "currency", default: "EGP", null: false
    t.decimal "subtotal_price", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "total_tax", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "total_shipping", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "total_discount", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "total_price", precision: 12, scale: 2, default: "0.0", null: false
    t.string "customer_email"
    t.string "customer_name"
    t.jsonb "shipping_address", default: {}, null: false
    t.jsonb "billing_address", default: {}, null: false
    t.text "notes"
    t.datetime "placed_at", null: false
    t.datetime "cancelled_at"
    t.bigint "shopify_order_id"
    t.datetime "shopify_updated_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.uuid "customer_id"
    t.bigint "shopify_customer_id"
    t.bigint "location_id"
    t.jsonb "tags", default: [], null: false
    t.string "delivery_method"
    t.integer "items_count", default: 0, null: false
    t.jsonb "payment_gateway_names", default: [], null: false
    t.string "risk_level"
    t.string "cancel_reason"
    t.datetime "closed_at"
    t.decimal "total_outstanding", precision: 12, scale: 2, default: "0.0", null: false
    t.string "shopify_order_status_url"
    t.decimal "total_refunded", precision: 12, scale: 2, default: "0.0", null: false
    t.string "last_delivery_status"
    t.index ["created_at"], name: "index_orders_on_created_at"
    t.index ["customer_email"], name: "index_orders_on_customer_email"
    t.index ["customer_id"], name: "index_orders_on_customer_id"
    t.index ["customer_name"], name: "index_orders_on_customer_name"
    t.index ["financial_status"], name: "index_orders_on_financial_status"
    t.index ["fulfillment_status"], name: "index_orders_on_fulfillment_status"
    t.index ["items_count"], name: "index_orders_on_items_count"
    t.index ["last_delivery_status"], name: "index_orders_on_last_delivery_status"
    t.index ["order_number"], name: "index_orders_on_order_number", unique: true
    t.index ["placed_at"], name: "index_orders_on_placed_at"
    t.index ["shopify_customer_id"], name: "index_orders_on_shopify_customer_id", where: "(shopify_customer_id IS NOT NULL)"
    t.index ["shopify_order_id"], name: "index_orders_on_shopify_order_id", unique: true, where: "(shopify_order_id IS NOT NULL)"
    t.index ["status"], name: "index_orders_on_status"
    t.index ["tags"], name: "index_orders_on_tags", using: :gin
    t.index ["total_price"], name: "index_orders_on_total_price"
    t.index ["total_refunded"], name: "index_orders_on_total_refunded"
    t.index ["updated_at"], name: "index_orders_on_updated_at"
  end

  create_table "permissions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "resource", null: false
    t.string "action", null: false
    t.string "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["resource", "action"], name: "index_permissions_on_resource_and_action", unique: true
  end

  create_table "product_images", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "product_id", null: false
    t.uuid "variant_id"
    t.text "src", null: false
    t.string "alt"
    t.integer "position", default: 1, null: false
    t.integer "width"
    t.integer "height"
    t.bigint "shopify_image_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id"], name: "index_product_images_on_product_id"
    t.index ["shopify_image_id"], name: "index_product_images_on_shopify_image_id", unique: true, where: "(shopify_image_id IS NOT NULL)"
    t.index ["variant_id"], name: "index_product_images_on_variant_id"
  end

  create_table "product_option_values", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "product_option_id", null: false
    t.string "value", null: false
    t.integer "position", default: 1, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["product_option_id", "value"], name: "idx_product_option_values_unique", unique: true
    t.index ["product_option_id"], name: "index_product_option_values_on_product_option_id"
  end

  create_table "product_options", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "product_id", null: false
    t.string "name", null: false
    t.integer "position", default: 1, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["product_id", "name"], name: "index_product_options_on_product_id_and_name", unique: true
    t.index ["product_id"], name: "index_product_options_on_product_id"
  end

  create_table "production_orders", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "number", null: false
    t.uuid "parent_variant_id", null: false
    t.uuid "warehouse_id", null: false
    t.integer "quantity", null: false
    t.string "status", default: "draft", null: false
    t.uuid "created_by_id"
    t.string "notes"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.datetime "cancelled_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "production_mode", default: "single", null: false
    t.decimal "unit_cost", precision: 14, scale: 4, default: "0.0"
    t.string "cost_currency", default: "USD"
    t.index ["created_by_id"], name: "index_production_orders_on_created_by_id"
    t.index ["number"], name: "index_production_orders_on_number", unique: true
    t.index ["parent_variant_id"], name: "index_production_orders_on_parent_variant_id"
    t.index ["status"], name: "index_production_orders_on_status"
    t.index ["warehouse_id"], name: "index_production_orders_on_warehouse_id"
  end

  create_table "production_stages", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "production_order_id", null: false
    t.integer "position", default: 0, null: false
    t.string "name", null: false
    t.string "status", default: "pending", null: false
    t.uuid "supplier_id"
    t.decimal "unit_cost", precision: 14, scale: 4, default: "0.0"
    t.string "cost_currency", default: "USD"
    t.datetime "started_at"
    t.datetime "completed_at"
    t.string "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["production_order_id", "position"], name: "idx_production_stages_order_position_uniq", unique: true
    t.index ["production_order_id"], name: "index_production_stages_on_production_order_id"
    t.index ["status"], name: "index_production_stages_on_status"
    t.index ["supplier_id"], name: "index_production_stages_on_supplier_id"
  end

  create_table "products", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "title", null: false
    t.string "handle", null: false
    t.string "status", default: "active", null: false
    t.string "vendor"
    t.string "product_type"
    t.text "description"
    t.bigint "shopify_product_id"
    t.datetime "shopify_updated_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "tags", default: [], null: false
    t.string "seo_title"
    t.text "seo_description"
    t.string "template_suffix"
    t.datetime "published_at"
    t.string "published_scope", default: "web", null: false
    t.boolean "gift_card", default: false, null: false
    t.jsonb "metafields", default: [], null: false
    t.string "source", default: "manual", null: false
    t.index ["handle"], name: "index_products_on_handle", unique: true
    t.index ["shopify_product_id"], name: "index_products_on_shopify_product_id", unique: true, where: "(shopify_product_id IS NOT NULL)"
    t.index ["source"], name: "index_products_on_source"
    t.index ["status"], name: "index_products_on_status"
    t.index ["tags"], name: "index_products_on_tags", using: :gin
  end

  create_table "purchase_order_line_items", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "purchase_order_id", null: false
    t.uuid "variant_id"
    t.string "sku"
    t.string "title"
    t.integer "quantity_ordered", default: 0, null: false
    t.integer "quantity_received", default: 0, null: false
    t.decimal "unit_cost", precision: 14, scale: 2, default: "0.0", null: false
    t.decimal "subtotal", precision: 14, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["purchase_order_id"], name: "idx_po_line_items_po"
    t.index ["variant_id", "created_at"], name: "idx_po_line_items_variant_created_at_desc", order: { created_at: :desc }
    t.index ["variant_id"], name: "index_purchase_order_line_items_on_variant_id"
  end

  create_table "purchase_orders", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "po_number", null: false
    t.uuid "supplier_id", null: false
    t.uuid "warehouse_id"
    t.string "status", default: "draft", null: false
    t.string "currency", default: "EGP", null: false
    t.decimal "subtotal", precision: 14, scale: 2, default: "0.0", null: false
    t.decimal "total_tax", precision: 14, scale: 2, default: "0.0", null: false
    t.decimal "total_shipping", precision: 14, scale: 2, default: "0.0", null: false
    t.decimal "total", precision: 14, scale: 2, default: "0.0", null: false
    t.datetime "ordered_at"
    t.datetime "expected_at"
    t.datetime "received_at"
    t.uuid "created_by_id"
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_id"], name: "index_purchase_orders_on_created_by_id"
    t.index ["po_number"], name: "index_purchase_orders_on_po_number", unique: true
    t.index ["status"], name: "index_purchase_orders_on_status"
    t.index ["supplier_id"], name: "index_purchase_orders_on_supplier_id"
    t.index ["warehouse_id"], name: "index_purchase_orders_on_warehouse_id"
  end

  create_table "refund_line_items", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "refund_id", null: false
    t.uuid "order_line_item_id"
    t.bigint "shopify_line_item_id"
    t.integer "quantity", default: 0, null: false
    t.decimal "subtotal", precision: 14, scale: 2, default: "0.0", null: false
    t.boolean "restock", default: false, null: false
    t.string "restock_type"
    t.bigint "location_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_line_item_id"], name: "index_refund_line_items_on_order_line_item_id"
    t.index ["refund_id", "shopify_line_item_id"], name: "idx_refund_line_items_refund_shopify_line", unique: true, where: "(shopify_line_item_id IS NOT NULL)"
    t.index ["refund_id"], name: "index_refund_line_items_on_refund_id"
  end

  create_table "refunds", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "order_id", null: false
    t.bigint "shopify_refund_id"
    t.decimal "amount", precision: 14, scale: 2, default: "0.0", null: false
    t.string "currency", default: "EGP", null: false
    t.string "reason"
    t.text "note"
    t.boolean "restock", default: false, null: false
    t.boolean "inventory_restocked", default: false, null: false
    t.datetime "processed_at"
    t.datetime "shopify_updated_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.jsonb "transactions", default: [], null: false
    t.string "status", default: "processed", null: false
    t.string "kind", default: "manual", null: false
    t.string "idempotency_key"
    t.string "content_hash"
    t.index ["content_hash"], name: "index_refunds_on_content_hash"
    t.index ["idempotency_key"], name: "index_refunds_on_idempotency_key", unique: true, where: "(idempotency_key IS NOT NULL)"
    t.index ["kind"], name: "index_refunds_on_kind"
    t.index ["order_id", "processed_at"], name: "idx_refunds_order_processed_at_desc", order: { processed_at: :desc }
    t.index ["order_id"], name: "index_refunds_on_order_id"
    t.index ["processed_at"], name: "index_refunds_on_processed_at"
    t.index ["shopify_refund_id"], name: "index_refunds_on_shopify_refund_id", unique: true, where: "(shopify_refund_id IS NOT NULL)"
    t.index ["status"], name: "index_refunds_on_status"
  end

  create_table "role_permissions", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "role_id", null: false
    t.uuid "permission_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["permission_id"], name: "index_role_permissions_on_permission_id"
    t.index ["role_id", "permission_id"], name: "index_role_permissions_on_role_id_and_permission_id", unique: true
    t.index ["role_id"], name: "index_role_permissions_on_role_id"
  end

  create_table "roles", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.string "description"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_roles_on_name", unique: true
  end

  create_table "shipment_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "fulfillment_id", null: false
    t.string "kind", null: false
    t.jsonb "payload", default: {}, null: false
    t.uuid "actor_id"
    t.string "dedupe_key"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["dedupe_key"], name: "index_shipment_events_on_dedupe_key", unique: true, where: "(dedupe_key IS NOT NULL)"
    t.index ["fulfillment_id", "created_at"], name: "index_shipment_events_on_fulfillment_id_and_created_at"
    t.index ["kind"], name: "index_shipment_events_on_kind"
  end

  create_table "shopify_mappings", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "local_type", null: false
    t.uuid "local_id", null: false
    t.string "shopify_type", null: false
    t.string "shopify_gid", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["local_type", "local_id"], name: "index_shopify_mappings_on_local"
    t.index ["shopify_gid"], name: "index_shopify_mappings_on_shopify_gid", unique: true
  end

  create_table "stock_items", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "variant_id", null: false
    t.uuid "warehouse_id", null: false
    t.integer "quantity_on_hand", default: 0, null: false
    t.integer "quantity_reserved", default: 0, null: false
    t.integer "low_stock_threshold", default: 5, null: false
    t.bigint "shopify_inventory_level_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.integer "quantity_unavailable", default: 0, null: false
    t.string "unavailability_reason"
    t.index ["shopify_inventory_level_id"], name: "index_stock_items_on_shopify_inventory_level_id", unique: true, where: "(shopify_inventory_level_id IS NOT NULL)"
    t.index ["variant_id", "warehouse_id"], name: "index_stock_items_on_variant_id_and_warehouse_id", unique: true
    t.index ["variant_id"], name: "index_stock_items_on_variant_id"
    t.index ["warehouse_id"], name: "index_stock_items_on_warehouse_id"
  end

  create_table "stock_movements", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "stock_item_id", null: false
    t.integer "delta", null: false
    t.string "reason", null: false
    t.string "reference_type"
    t.string "reference_id"
    t.integer "snapshot_before", null: false
    t.integer "snapshot_after", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "note"
    t.index ["stock_item_id"], name: "index_stock_movements_on_stock_item_id"
  end

  create_table "stock_reservations", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "order_line_item_id", null: false
    t.uuid "stock_item_id", null: false
    t.integer "quantity", null: false
    t.string "status", default: "active", null: false
    t.string "note"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["order_line_item_id", "status"], name: "index_stock_reservations_on_order_line_item_id_and_status"
    t.index ["order_line_item_id", "stock_item_id"], name: "idx_stock_reservations_active_line_stock", unique: true, where: "((status)::text = 'active'::text)"
    t.index ["stock_item_id", "status"], name: "index_stock_reservations_on_stock_item_id_and_status"
  end

  create_table "suppliers", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.string "email"
    t.string "phone"
    t.jsonb "address", default: {}, null: false
    t.string "tax_id"
    t.string "currency", default: "EGP", null: false
    t.jsonb "payment_terms", default: {}, null: false
    t.string "status", default: "active", null: false
    t.text "notes"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "supplier_code"
    t.integer "lead_time_days"
    t.index ["name"], name: "index_suppliers_on_name"
    t.index ["status"], name: "index_suppliers_on_status"
    t.index ["supplier_code"], name: "index_suppliers_on_supplier_code", unique: true, where: "(supplier_code IS NOT NULL)"
  end

  create_table "sync_cursors", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "source", null: false
    t.string "resource", null: false
    t.string "last_cursor"
    t.datetime "last_synced_at"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["source", "resource"], name: "index_sync_cursors_on_source_and_resource", unique: true
  end

  create_table "user_roles", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "user_id", null: false
    t.uuid "role_id", null: false
    t.uuid "warehouse_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["role_id"], name: "index_user_roles_on_role_id"
    t.index ["user_id", "role_id", "warehouse_id"], name: "index_user_roles_unique", unique: true
    t.index ["user_id"], name: "index_user_roles_on_user_id"
  end

  create_table "users", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "first_name", default: "", null: false
    t.string "last_name", default: "", null: false
    t.string "reset_password_token"
    t.datetime "reset_password_sent_at"
    t.datetime "remember_created_at"
    t.boolean "active", default: true, null: false
    t.datetime "last_login_at"
    t.string "jti", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["jti"], name: "index_users_on_jti", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "variants", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.uuid "product_id", null: false
    t.string "sku"
    t.string "title", default: "Default Title", null: false
    t.decimal "price", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "compare_at_price", precision: 12, scale: 2
    t.string "barcode"
    t.integer "position", default: 1, null: false
    t.bigint "shopify_variant_id"
    t.bigint "shopify_inventory_item_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "option1"
    t.string "option2"
    t.string "option3"
    t.decimal "weight", precision: 10, scale: 3
    t.string "weight_unit", default: "kg", null: false
    t.string "inventory_policy", default: "deny", null: false
    t.string "inventory_management"
    t.boolean "requires_shipping", default: true, null: false
    t.boolean "taxable", default: true, null: false
    t.string "fulfillment_service", default: "manual", null: false
    t.string "hs_code"
    t.string "country_of_origin"
    t.decimal "cost_per_item", precision: 12, scale: 2
    t.decimal "cost", precision: 12, scale: 2
    t.decimal "last_purchase_cost", precision: 12, scale: 2
    t.index ["product_id"], name: "index_variants_on_product_id"
    t.index ["shopify_inventory_item_id"], name: "index_variants_on_shopify_inventory_item_id"
    t.index ["shopify_variant_id"], name: "index_variants_on_shopify_variant_id", unique: true, where: "(shopify_variant_id IS NOT NULL)"
    t.index ["sku"], name: "index_variants_on_sku", unique: true, where: "((sku IS NOT NULL) AND ((sku)::text <> ''::text))"
  end

  create_table "warehouses", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "name", null: false
    t.string "code", null: false
    t.string "address"
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.bigint "shopify_location_id"
    t.string "kind", default: "own", null: false
    t.string "partner_name"
    t.string "partner_email"
    t.string "partner_phone"
    t.decimal "commission_rate", precision: 5, scale: 4
    t.string "currency", limit: 3, default: "EGP"
    t.text "notes"
    t.index ["code"], name: "index_warehouses_on_code", unique: true
    t.index ["shopify_location_id"], name: "index_warehouses_on_shopify_location_id", unique: true, where: "(shopify_location_id IS NOT NULL)"
  end

  create_table "webhook_events", id: :uuid, default: -> { "gen_random_uuid()" }, force: :cascade do |t|
    t.string "source", null: false
    t.string "topic", null: false
    t.string "external_id", null: false
    t.jsonb "payload", default: {}, null: false
    t.datetime "received_at", null: false
    t.datetime "processed_at"
    t.text "error"
    t.integer "attempts", default: 0, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["processed_at"], name: "index_webhook_events_on_processed_at"
    t.index ["source", "external_id"], name: "index_webhook_events_on_source_external_id", unique: true
    t.index ["topic"], name: "index_webhook_events_on_topic"
  end

  add_foreign_key "accounts", "accounts", column: "parent_id"
  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "bom_items", "variants", column: "component_variant_id"
  add_foreign_key "bom_items", "variants", column: "parent_variant_id"
  add_foreign_key "collection_products", "collections", on_delete: :cascade, validate: false
  add_foreign_key "collection_products", "products", on_delete: :cascade, validate: false
  add_foreign_key "fulfillment_line_items", "fulfillments"
  add_foreign_key "fulfillment_line_items", "order_line_items"
  add_foreign_key "fulfillments", "orders"
  add_foreign_key "journal_entries", "journal_entries", column: "reversal_of_id"
  add_foreign_key "journal_lines", "accounts"
  add_foreign_key "journal_lines", "journal_entries"
  add_foreign_key "order_line_items", "orders"
  add_foreign_key "order_line_items", "variants"
  add_foreign_key "orders", "customers"
  add_foreign_key "product_images", "products"
  add_foreign_key "product_images", "variants"
  add_foreign_key "product_option_values", "product_options"
  add_foreign_key "product_options", "products"
  add_foreign_key "production_orders", "users", column: "created_by_id"
  add_foreign_key "production_orders", "variants", column: "parent_variant_id"
  add_foreign_key "production_orders", "warehouses"
  add_foreign_key "production_stages", "production_orders"
  add_foreign_key "production_stages", "suppliers"
  add_foreign_key "purchase_order_line_items", "purchase_orders"
  add_foreign_key "purchase_order_line_items", "variants"
  add_foreign_key "purchase_orders", "suppliers"
  add_foreign_key "purchase_orders", "users", column: "created_by_id"
  add_foreign_key "purchase_orders", "warehouses"
  add_foreign_key "refund_line_items", "order_line_items"
  add_foreign_key "refund_line_items", "refunds"
  add_foreign_key "refunds", "orders"
  add_foreign_key "role_permissions", "permissions"
  add_foreign_key "role_permissions", "roles"
  add_foreign_key "shipment_events", "fulfillments", on_delete: :cascade
  add_foreign_key "shipment_events", "users", column: "actor_id"
  add_foreign_key "stock_items", "variants"
  add_foreign_key "stock_items", "warehouses"
  add_foreign_key "stock_movements", "stock_items"
  add_foreign_key "stock_reservations", "order_line_items", on_delete: :cascade
  add_foreign_key "stock_reservations", "stock_items", on_delete: :restrict
  add_foreign_key "user_roles", "roles"
  add_foreign_key "user_roles", "users"
  add_foreign_key "variants", "products"
end
