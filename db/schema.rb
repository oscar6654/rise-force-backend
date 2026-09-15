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

ActiveRecord::Schema[8.1].define(version: 2026_09_15_100001) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "assortment_items", force: :cascade do |t|
    t.bigint "assortment_id", null: false
    t.datetime "created_at", null: false
    t.boolean "must_stock", default: true, null: false
    t.integer "priority", default: 0, null: false
    t.bigint "product_id", null: false
    t.datetime "updated_at", null: false
    t.index ["assortment_id", "product_id"], name: "index_assortment_items_on_assortment_id_and_product_id", unique: true
    t.index ["assortment_id"], name: "index_assortment_items_on_assortment_id"
    t.index ["product_id"], name: "index_assortment_items_on_product_id"
  end

  create_table "assortment_types", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_assortment_types_on_code", unique: true
  end

  create_table "assortments", force: :cascade do |t|
    t.bigint "assortment_type_id", null: false
    t.bigint "branch_id"
    t.bigint "channel_id"
    t.datetime "created_at", null: false
    t.date "effective_from"
    t.date "effective_to"
    t.string "name", null: false
    t.integer "status", default: 0, null: false
    t.bigint "store_category_ref_id"
    t.datetime "updated_at", null: false
    t.index ["assortment_type_id"], name: "index_assortments_on_assortment_type_id"
    t.index ["branch_id"], name: "index_assortments_on_branch_id"
    t.index ["channel_id"], name: "index_assortments_on_channel_id"
    t.index ["store_category_ref_id"], name: "index_assortments_on_store_category_ref_id"
  end

  create_table "branches", force: :cascade do |t|
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.string "region"
    t.integer "status", default: 0, null: false
    t.string "timezone", default: "Asia/Manila", null: false
    t.datetime "updated_at", null: false
    t.string "vcsi_branch_ref"
    t.index ["code"], name: "index_branches_on_code", unique: true
    t.index ["vcsi_branch_ref"], name: "index_branches_on_vcsi_branch_ref"
  end

  create_table "brands", force: :cascade do |t|
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "sort_order", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_brands_on_code", unique: true
  end

  create_table "channels", force: :cascade do |t|
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.string "name", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_channels_on_code", unique: true
  end

  create_table "competitor_price_checks", force: :cascade do |t|
    t.string "client_uuid", null: false
    t.string "competitor_name"
    t.decimal "competitor_price", precision: 12, scale: 2
    t.datetime "created_at", null: false
    t.text "notes"
    t.decimal "our_price", precision: 12, scale: 2
    t.bigint "product_id"
    t.string "product_label"
    t.datetime "updated_at", null: false
    t.bigint "visit_id", null: false
    t.index ["client_uuid"], name: "index_competitor_price_checks_on_client_uuid", unique: true
    t.index ["product_id"], name: "index_competitor_price_checks_on_product_id"
    t.index ["visit_id"], name: "index_competitor_price_checks_on_visit_id"
  end

  create_table "device_tokens", force: :cascade do |t|
    t.string "app_version"
    t.datetime "created_at", null: false
    t.string "device_id"
    t.string "jti", null: false
    t.datetime "last_used_at"
    t.string "platform"
    t.datetime "refresh_expires_at"
    t.string "refresh_token_digest"
    t.datetime "revoked_at"
    t.bigint "seller_id", null: false
    t.datetime "updated_at", null: false
    t.index ["jti"], name: "index_device_tokens_on_jti", unique: true
    t.index ["seller_id", "device_id"], name: "index_device_tokens_on_seller_id_and_device_id"
    t.index ["seller_id"], name: "index_device_tokens_on_seller_id"
  end

  create_table "incentive_schemes", force: :cascade do |t|
    t.bigint "branch_id"
    t.jsonb "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.date "effective_from"
    t.date "effective_to"
    t.string "name", null: false
    t.integer "scheme_type", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["branch_id"], name: "index_incentive_schemes_on_branch_id"
  end

  create_table "job_logs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "error_count", default: 0, null: false
    t.string "filename"
    t.datetime "finished_at"
    t.integer "job_type", null: false
    t.integer "processed_rows", default: 0, null: false
    t.jsonb "rejected_records_data", default: [], null: false
    t.jsonb "result_summary", default: {}, null: false
    t.integer "skipped_rows", default: 0, null: false
    t.datetime "started_at"
    t.integer "status", default: 0, null: false
    t.integer "total_rows", default: 0, null: false
    t.bigint "triggered_by_id"
    t.datetime "updated_at", null: false
    t.index ["created_at"], name: "index_job_logs_on_created_at"
    t.index ["job_type", "status"], name: "index_job_logs_on_job_type_and_status"
    t.index ["triggered_by_id"], name: "index_job_logs_on_triggered_by_id"
  end

  create_table "order_batches", force: :cascade do |t|
    t.string "batch_number", null: false
    t.bigint "branch_id", null: false
    t.datetime "created_at", null: false
    t.string "download_file_ref"
    t.datetime "downloaded_at"
    t.bigint "downloaded_by_id"
    t.datetime "invoiced_at"
    t.datetime "locked_at"
    t.bigint "locked_by_id"
    t.integer "order_count", default: 0, null: false
    t.bigint "seller_id"
    t.integer "sequence", null: false
    t.integer "status", default: 0, null: false
    t.decimal "total_amount", precision: 14, scale: 2, default: "0.0", null: false
    t.datetime "updated_at", null: false
    t.index ["batch_number"], name: "index_order_batches_on_batch_number", unique: true
    t.index ["branch_id", "seller_id", "sequence"], name: "index_order_batches_on_branch_id_and_seller_id_and_sequence", unique: true
    t.index ["branch_id", "seller_id", "status"], name: "index_order_batches_on_branch_id_and_seller_id_and_status"
    t.index ["branch_id", "seller_id"], name: "index_one_open_batch_per_branch_seller", unique: true, where: "(status = 0)"
    t.index ["branch_id"], name: "index_order_batches_on_branch_id"
    t.index ["downloaded_by_id"], name: "index_order_batches_on_downloaded_by_id"
    t.index ["locked_by_id"], name: "index_order_batches_on_locked_by_id"
    t.index ["seller_id"], name: "index_order_batches_on_seller_id"
  end

  create_table "order_lines", force: :cascade do |t|
    t.decimal "base_price", precision: 12, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.decimal "line_discount", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "line_total", precision: 14, scale: 2, default: "0.0", null: false
    t.integer "line_type", default: 0, null: false
    t.decimal "markup_rate", precision: 7, scale: 4, default: "0.0", null: false
    t.bigint "order_id", null: false
    t.bigint "product_id", null: false
    t.bigint "promo_id"
    t.decimal "quantity", precision: 12, scale: 2, default: "0.0", null: false
    t.decimal "unit_price", precision: 12, scale: 2, default: "0.0", null: false
    t.integer "uom", default: 0, null: false
    t.datetime "updated_at", null: false
    t.string "vcsi_product_ref"
    t.index ["order_id"], name: "index_order_lines_on_order_id"
    t.index ["product_id"], name: "index_order_lines_on_product_id"
    t.index ["promo_id"], name: "index_order_lines_on_promo_id"
  end

  create_table "orders", force: :cascade do |t|
    t.bigint "branch_id", null: false
    t.string "client_uuid", null: false
    t.datetime "created_at", null: false
    t.text "notes"
    t.bigint "order_batch_id"
    t.string "order_number"
    t.datetime "ordered_at"
    t.bigint "pricing_version_id"
    t.jsonb "promo_summary", default: {}, null: false
    t.bigint "route_id"
    t.bigint "seller_id", null: false
    t.integer "status", default: 0, null: false
    t.bigint "store_id", null: false
    t.datetime "synced_at"
    t.decimal "total_amount", precision: 14, scale: 2, default: "0.0", null: false
    t.datetime "updated_at", null: false
    t.bigint "visit_id"
    t.index ["branch_id", "seller_id", "status"], name: "index_orders_on_branch_id_and_seller_id_and_status"
    t.index ["branch_id"], name: "index_orders_on_branch_id"
    t.index ["client_uuid"], name: "index_orders_on_client_uuid", unique: true
    t.index ["order_batch_id"], name: "index_orders_on_order_batch_id"
    t.index ["order_number"], name: "index_orders_on_order_number", unique: true, where: "(order_number IS NOT NULL)"
    t.index ["pricing_version_id"], name: "index_orders_on_pricing_version_id"
    t.index ["route_id"], name: "index_orders_on_route_id"
    t.index ["seller_id"], name: "index_orders_on_seller_id"
    t.index ["store_id", "ordered_at"], name: "index_orders_on_store_id_and_ordered_at"
    t.index ["store_id"], name: "index_orders_on_store_id"
    t.index ["visit_id"], name: "index_orders_on_visit_id"
  end

  create_table "permissions", force: :cascade do |t|
    t.string "action", null: false
    t.datetime "created_at", null: false
    t.string "description"
    t.string "resource", null: false
    t.datetime "updated_at", null: false
    t.index ["resource", "action"], name: "index_permissions_on_resource_and_action", unique: true
  end

  create_table "planograms", force: :cascade do |t|
    t.bigint "channel_id", null: false
    t.datetime "created_at", null: false
    t.date "effective_date"
    t.integer "status", default: 0, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.bigint "uploaded_by_id"
    t.index ["channel_id", "status"], name: "index_planograms_on_channel_id_and_status"
    t.index ["channel_id"], name: "index_planograms_on_channel_id"
    t.index ["uploaded_by_id"], name: "index_planograms_on_uploaded_by_id"
  end

  create_table "pricing_rules", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.decimal "markup_rate", precision: 7, scale: 4, default: "0.0", null: false
    t.bigint "pricing_version_id", null: false
    t.bigint "product_tier_id"
    t.bigint "store_category_id"
    t.datetime "updated_at", null: false
    t.index ["pricing_version_id", "store_category_id", "product_tier_id"], name: "index_pricing_rules_on_version_cat_tier", unique: true
    t.index ["pricing_version_id"], name: "index_pricing_rules_on_pricing_version_id"
    t.index ["product_tier_id"], name: "index_pricing_rules_on_product_tier_id"
    t.index ["store_category_id"], name: "index_pricing_rules_on_store_category_id"
  end

  create_table "pricing_versions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "effective_date", null: false
    t.string "name"
    t.text "notes"
    t.datetime "published_at"
    t.bigint "published_by_id"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.integer "version_number", null: false
    t.index ["published_by_id"], name: "index_pricing_versions_on_published_by_id"
    t.index ["status", "effective_date"], name: "index_pricing_versions_on_status_and_effective_date"
    t.index ["version_number"], name: "index_pricing_versions_on_version_number", unique: true
  end

  create_table "product_categories", force: :cascade do |t|
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_product_categories_on_code", unique: true
  end

  create_table "product_channels", force: :cascade do |t|
    t.bigint "channel_id", null: false
    t.datetime "created_at", null: false
    t.bigint "product_id", null: false
    t.datetime "updated_at", null: false
    t.index ["channel_id"], name: "index_product_channels_on_channel_id"
    t.index ["product_id", "channel_id"], name: "index_product_channels_on_product_id_and_channel_id", unique: true
    t.index ["product_id"], name: "index_product_channels_on_product_id"
  end

  create_table "product_tiers", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.integer "sort_order", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_product_tiers_on_code", unique: true
  end

  create_table "products", force: :cascade do |t|
    t.string "abc_class"
    t.string "brand_form"
    t.bigint "brand_id"
    t.decimal "case_cost", precision: 15, scale: 2
    t.decimal "caseheight", precision: 10, scale: 4
    t.integer "casesperpallet"
    t.integer "casestatfactor"
    t.decimal "casevolume", precision: 10, scale: 4
    t.decimal "caseweight", precision: 10, scale: 4
    t.datetime "created_at", null: false
    t.string "cs_barcode"
    t.string "desc2"
    t.string "description", null: false
    t.string "it_barcode"
    t.decimal "item_cost", precision: 15, scale: 2
    t.integer "items_per_shrinkwrap"
    t.integer "layersperpallet"
    t.string "msq"
    t.string "nspacksize"
    t.string "nspacktype"
    t.string "ordering_unit"
    t.string "ovsoldcostmethod"
    t.integer "pcs_per_case"
    t.bigint "product_category_id"
    t.bigint "product_tier_id"
    t.string "purchase_uom"
    t.string "selling_uom"
    t.integer "shrinkwraps_per_case"
    t.string "sku", null: false
    t.string "slideoutcode"
    t.integer "status", default: 0, null: false
    t.string "stock_uom"
    t.string "sw_barcode"
    t.string "tax_code"
    t.datetime "updated_at", null: false
    t.string "variant_code"
    t.string "variant_name"
    t.string "vcsi_product_ref"
    t.index ["brand_id"], name: "index_products_on_brand_id"
    t.index ["cs_barcode"], name: "index_products_on_cs_barcode"
    t.index ["it_barcode"], name: "index_products_on_it_barcode"
    t.index ["product_category_id"], name: "index_products_on_product_category_id"
    t.index ["product_tier_id"], name: "index_products_on_product_tier_id"
    t.index ["sku"], name: "index_products_on_sku", unique: true
    t.index ["sw_barcode"], name: "index_products_on_sw_barcode"
    t.index ["vcsi_product_ref"], name: "index_products_on_vcsi_product_ref"
  end

  create_table "promo_eligibilities", force: :cascade do |t|
    t.bigint "branch_id"
    t.bigint "channel_id"
    t.datetime "created_at", null: false
    t.bigint "promo_id", null: false
    t.bigint "store_category_ref_id"
    t.datetime "updated_at", null: false
    t.index ["branch_id"], name: "index_promo_eligibilities_on_branch_id"
    t.index ["channel_id"], name: "index_promo_eligibilities_on_channel_id"
    t.index ["promo_id"], name: "index_promo_eligibilities_on_promo_id"
    t.index ["store_category_ref_id"], name: "index_promo_eligibilities_on_store_category_ref_id"
  end

  create_table "promo_lines", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.decimal "discount_amount", precision: 12, scale: 2
    t.decimal "discount_rate", precision: 7, scale: 4
    t.decimal "fixed_price", precision: 12, scale: 2
    t.string "it_barcode"
    t.integer "min_qty"
    t.bigint "product_id"
    t.bigint "promo_id", null: false
    t.integer "reward_qty"
    t.integer "role", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["it_barcode"], name: "index_promo_lines_on_it_barcode"
    t.index ["product_id"], name: "index_promo_lines_on_product_id"
    t.index ["promo_id"], name: "index_promo_lines_on_promo_id"
  end

  create_table "promos", force: :cascade do |t|
    t.string "code", null: false
    t.jsonb "config", default: {}, null: false
    t.datetime "created_at", null: false
    t.bigint "created_by_id"
    t.text "description"
    t.date "end_date"
    t.integer "mechanic_type", default: 0, null: false
    t.string "name", null: false
    t.integer "per_store_limit"
    t.date "start_date"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_promos_on_code", unique: true
    t.index ["created_by_id"], name: "index_promos_on_created_by_id"
    t.index ["status", "start_date", "end_date"], name: "index_promos_on_status_and_start_date_and_end_date"
  end

  create_table "role_permissions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "permission_id", null: false
    t.bigint "role_id", null: false
    t.datetime "updated_at", null: false
    t.index ["permission_id"], name: "index_role_permissions_on_permission_id"
    t.index ["role_id", "permission_id"], name: "index_role_permissions_on_role_id_and_permission_id", unique: true
    t.index ["role_id"], name: "index_role_permissions_on_role_id"
  end

  create_table "roles", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.datetime "created_at", null: false
    t.string "description"
    t.string "name", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_roles_on_name", unique: true
  end

  create_table "routes", force: :cascade do |t|
    t.bigint "branch_id", null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "name"
    t.bigint "seller_id"
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["branch_id", "code"], name: "index_routes_on_branch_id_and_code", unique: true
    t.index ["branch_id"], name: "index_routes_on_branch_id"
    t.index ["seller_id"], name: "index_routes_on_seller_id"
  end

  create_table "seller_daily_stats", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "goal_met", default: false, null: false
    t.integer "orders_count", default: 0, null: false
    t.integer "planned", default: 0, null: false
    t.integer "productive_calls", default: 0, null: false
    t.bigint "seller_id", null: false
    t.date "stat_date", null: false
    t.datetime "updated_at", null: false
    t.integer "visited", default: 0, null: false
    t.index ["seller_id", "stat_date"], name: "index_seller_daily_stats_on_seller_id_and_stat_date", unique: true
    t.index ["seller_id"], name: "index_seller_daily_stats_on_seller_id"
  end

  create_table "seller_targets", force: :cascade do |t|
    t.bigint "branch_id"
    t.datetime "created_at", null: false
    t.date "period_date", null: false
    t.integer "period_type", default: 2, null: false
    t.bigint "seller_id", null: false
    t.datetime "synced_at"
    t.decimal "target_amount", precision: 14, scale: 2, default: "0.0", null: false
    t.decimal "target_quantity", precision: 14, scale: 2
    t.datetime "updated_at", null: false
    t.index ["branch_id"], name: "index_seller_targets_on_branch_id"
    t.index ["seller_id", "period_type", "period_date"], name: "idx_on_seller_id_period_type_period_date_1b205bac0d", unique: true
    t.index ["seller_id"], name: "index_seller_targets_on_seller_id"
  end

  create_table "sellers", force: :cascade do |t|
    t.bigint "branch_id", null: false
    t.datetime "created_at", null: false
    t.string "device_id"
    t.datetime "device_registered_at"
    t.string "gsm_name"
    t.datetime "last_sync_at"
    t.string "name", null: false
    t.string "om_name"
    t.string "pin_digest"
    t.decimal "sales_target", precision: 15, scale: 2
    t.string "seller_code", null: false
    t.integer "status", default: 0, null: false
    t.string "supervisor_name"
    t.datetime "updated_at", null: false
    t.bigint "user_id"
    t.datetime "vcsi_pulled_at"
    t.string "vcsi_sales_rep_ref"
    t.index ["branch_id", "status"], name: "index_sellers_on_branch_id_and_status"
    t.index ["branch_id"], name: "index_sellers_on_branch_id"
    t.index ["seller_code"], name: "index_sellers_on_seller_code", unique: true
    t.index ["user_id"], name: "index_sellers_on_user_id"
    t.index ["vcsi_sales_rep_ref"], name: "index_sellers_on_vcsi_sales_rep_ref"
  end

  create_table "sellout_snapshots", force: :cascade do |t|
    t.decimal "amount", precision: 14, scale: 2, default: "0.0", null: false
    t.bigint "branch_id"
    t.datetime "created_at", null: false
    t.date "period_date", null: false
    t.integer "period_type", default: 1, null: false
    t.bigint "product_id"
    t.decimal "quantity", precision: 14, scale: 2, default: "0.0", null: false
    t.jsonb "raw", default: {}, null: false
    t.bigint "seller_id"
    t.bigint "store_id"
    t.datetime "synced_at"
    t.datetime "updated_at", null: false
    t.index ["branch_id"], name: "index_sellout_snapshots_on_branch_id"
    t.index ["product_id"], name: "index_sellout_snapshots_on_product_id"
    t.index ["seller_id", "period_type", "period_date", "store_id", "product_id"], name: "index_sellout_snapshots_natural_key", unique: true
    t.index ["seller_id", "period_type", "period_date"], name: "index_sellout_snapshots_seller_grain", unique: true, where: "((store_id IS NULL) AND (product_id IS NULL))"
    t.index ["seller_id"], name: "index_sellout_snapshots_on_seller_id"
    t.index ["store_id", "period_type", "period_date"], name: "index_sellout_snapshots_store_grain", unique: true, where: "((seller_id IS NULL) AND (product_id IS NULL))"
    t.index ["store_id"], name: "index_sellout_snapshots_on_store_id"
  end

  create_table "sku_sellout_snapshots", force: :cascade do |t|
    t.decimal "amount", precision: 14, scale: 2, default: "0.0", null: false
    t.datetime "created_at", null: false
    t.string "it_barcode"
    t.date "period_date", null: false
    t.decimal "pieces", precision: 14, scale: 2, default: "0.0", null: false
    t.bigint "product_id"
    t.bigint "seller_id", null: false
    t.datetime "synced_at"
    t.datetime "updated_at", null: false
    t.index ["product_id"], name: "index_sku_sellout_snapshots_on_product_id"
    t.index ["seller_id", "product_id", "period_date"], name: "idx_sku_sellout_natural", unique: true
    t.index ["seller_id"], name: "index_sku_sellout_snapshots_on_seller_id"
  end

  create_table "stock_counts", force: :cascade do |t|
    t.string "client_uuid", null: false
    t.datetime "created_at", null: false
    t.integer "prefilled_from", default: 0, null: false
    t.bigint "product_id", null: false
    t.decimal "qty", precision: 12, scale: 2, default: "0.0", null: false
    t.datetime "updated_at", null: false
    t.bigint "visit_id", null: false
    t.index ["client_uuid"], name: "index_stock_counts_on_client_uuid", unique: true
    t.index ["product_id"], name: "index_stock_counts_on_product_id"
    t.index ["visit_id", "product_id"], name: "index_stock_counts_on_visit_id_and_product_id", unique: true
    t.index ["visit_id"], name: "index_stock_counts_on_visit_id"
  end

  create_table "stock_snapshots", force: :cascade do |t|
    t.date "as_of_date", null: false
    t.datetime "created_at", null: false
    t.bigint "product_id", null: false
    t.decimal "quantity", precision: 14, scale: 2, default: "0.0", null: false
    t.jsonb "raw", default: {}, null: false
    t.bigint "store_id", null: false
    t.datetime "synced_at"
    t.datetime "updated_at", null: false
    t.index ["product_id"], name: "index_stock_snapshots_on_product_id"
    t.index ["store_id", "product_id", "as_of_date"], name: "idx_on_store_id_product_id_as_of_date_6194f60507", unique: true
    t.index ["store_id"], name: "index_stock_snapshots_on_store_id"
  end

  create_table "store_categories", force: :cascade do |t|
    t.boolean "active", default: true, null: false
    t.string "code", null: false
    t.datetime "created_at", null: false
    t.string "letter"
    t.string "name", null: false
    t.integer "sort_order", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["code"], name: "index_store_categories_on_code", unique: true
  end

  create_table "store_registrations", force: :cascade do |t|
    t.string "address"
    t.bigint "branch_id", null: false
    t.bigint "channel_id"
    t.string "client_uuid", null: false
    t.string "contact_number"
    t.datetime "created_at", null: false
    t.bigint "created_store_id"
    t.jsonb "duplicate_flags", default: [], null: false
    t.bigint "duplicate_of_store_id"
    t.decimal "duplicate_score", precision: 5, scale: 2
    t.decimal "latitude", precision: 10, scale: 6
    t.decimal "longitude", precision: 10, scale: 6
    t.string "name", null: false
    t.string "owner_name"
    t.integer "proposed_category"
    t.bigint "provisional_store_id"
    t.text "rejection_reason"
    t.datetime "reviewed_at"
    t.bigint "reviewed_by_id"
    t.bigint "seller_id", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["branch_id", "status"], name: "index_store_registrations_on_branch_id_and_status"
    t.index ["branch_id"], name: "index_store_registrations_on_branch_id"
    t.index ["channel_id"], name: "index_store_registrations_on_channel_id"
    t.index ["client_uuid"], name: "index_store_registrations_on_client_uuid", unique: true
    t.index ["created_store_id"], name: "index_store_registrations_on_created_store_id"
    t.index ["duplicate_of_store_id"], name: "index_store_registrations_on_duplicate_of_store_id"
    t.index ["provisional_store_id"], name: "index_store_registrations_on_provisional_store_id"
    t.index ["reviewed_by_id"], name: "index_store_registrations_on_reviewed_by_id"
    t.index ["seller_id"], name: "index_store_registrations_on_seller_id"
  end

  create_table "store_sku_sellouts", force: :cascade do |t|
    t.decimal "amount", precision: 12, scale: 2, default: "0.0"
    t.datetime "created_at", null: false
    t.string "it_barcode", null: false
    t.date "period_date", null: false
    t.decimal "pieces", precision: 12, scale: 2, default: "0.0"
    t.jsonb "raw", default: {}
    t.bigint "store_id", null: false
    t.datetime "synced_at"
    t.datetime "updated_at", null: false
    t.index ["store_id", "it_barcode", "period_date"], name: "index_store_sku_sellouts_unique", unique: true
    t.index ["store_id", "period_date"], name: "index_store_sku_sellouts_on_store_id_and_period_date"
    t.index ["store_id"], name: "index_store_sku_sellouts_on_store_id"
  end

  create_table "store_targets", force: :cascade do |t|
    t.decimal "basis_amount", precision: 14, scale: 2
    t.bigint "branch_id"
    t.datetime "created_at", null: false
    t.decimal "growth_rate", precision: 7, scale: 4
    t.integer "months_used"
    t.date "period_date", null: false
    t.integer "period_type", default: 2, null: false
    t.bigint "store_id", null: false
    t.datetime "synced_at"
    t.decimal "target_amount", precision: 14, scale: 2, default: "0.0", null: false
    t.datetime "updated_at", null: false
    t.index ["branch_id"], name: "index_store_targets_on_branch_id"
    t.index ["store_id", "period_type", "period_date"], name: "index_store_targets_natural_key", unique: true
    t.index ["store_id"], name: "index_store_targets_on_store_id"
  end

  create_table "stores", force: :cascade do |t|
    t.string "address"
    t.bigint "branch_id", null: false
    t.string "chain"
    t.bigint "channel_id"
    t.string "contact_number"
    t.datetime "created_at", null: false
    t.decimal "discount_rate", precision: 7, scale: 4, default: "0.0", null: false
    t.string "distribution_type"
    t.decimal "latitude", precision: 10, scale: 6
    t.decimal "longitude", precision: 10, scale: 6
    t.string "name", null: false
    t.string "owner_name"
    t.string "provisional_code"
    t.bigint "route_id"
    t.string "segment"
    t.bigint "seller_id"
    t.integer "status", default: 1, null: false
    t.bigint "store_category_id"
    t.string "store_code"
    t.bigint "store_registration_id"
    t.string "sub_chain"
    t.string "tin"
    t.datetime "updated_at", null: false
    t.string "vcsi_customer_ref"
    t.integer "visit_day"
    t.integer "visit_frequency", default: 4, null: false
    t.integer "visit_sequence"
    t.integer "week_pattern", default: 0, null: false
    t.index ["branch_id"], name: "index_stores_on_branch_id"
    t.index ["channel_id"], name: "index_stores_on_channel_id"
    t.index ["name"], name: "index_stores_on_name_trgm", opclass: :gin_trgm_ops, using: :gin
    t.index ["provisional_code"], name: "index_stores_on_provisional_code", unique: true, where: "(provisional_code IS NOT NULL)"
    t.index ["route_id", "visit_day", "visit_sequence"], name: "index_stores_on_route_id_and_visit_day_and_visit_sequence"
    t.index ["route_id"], name: "index_stores_on_route_id"
    t.index ["seller_id"], name: "index_stores_on_seller_id"
    t.index ["store_category_id"], name: "index_stores_on_store_category_id"
    t.index ["store_code"], name: "index_stores_on_store_code", unique: true, where: "(store_code IS NOT NULL)"
    t.index ["store_registration_id"], name: "index_stores_on_store_registration_id"
    t.index ["vcsi_customer_ref"], name: "index_stores_on_vcsi_customer_ref"
  end

  create_table "system_settings", force: :cascade do |t|
    t.string "category", default: "general", null: false
    t.datetime "created_at", null: false
    t.string "description"
    t.boolean "encrypted", default: false, null: false
    t.string "key", null: false
    t.boolean "required", default: false, null: false
    t.string "test_status", default: "untested"
    t.datetime "updated_at", null: false
    t.text "value"
    t.string "value_type", default: "string", null: false
    t.index ["category"], name: "index_system_settings_on_category"
    t.index ["key"], name: "index_system_settings_on_key", unique: true
  end

  create_table "user_roles", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "role_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["role_id"], name: "index_user_roles_on_role_id"
    t.index ["user_id", "role_id"], name: "index_user_roles_on_user_id_and_role_id", unique: true
    t.index ["user_id"], name: "index_user_roles_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.bigint "branch_id"
    t.datetime "created_at", null: false
    t.datetime "current_sign_in_at"
    t.string "current_sign_in_ip"
    t.string "email", default: "", null: false
    t.string "encrypted_password", default: "", null: false
    t.string "first_name"
    t.string "last_name"
    t.datetime "last_sign_in_at"
    t.string "last_sign_in_ip"
    t.datetime "remember_created_at"
    t.datetime "reset_password_sent_at"
    t.string "reset_password_token"
    t.integer "sign_in_count", default: 0, null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["branch_id"], name: "index_users_on_branch_id"
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["reset_password_token"], name: "index_users_on_reset_password_token", unique: true
  end

  create_table "visit_photos", force: :cascade do |t|
    t.string "client_uuid", null: false
    t.datetime "created_at", null: false
    t.integer "kind", default: 0, null: false
    t.bigint "planogram_id"
    t.datetime "updated_at", null: false
    t.bigint "visit_id", null: false
    t.index ["client_uuid"], name: "index_visit_photos_on_client_uuid", unique: true
    t.index ["planogram_id"], name: "index_visit_photos_on_planogram_id"
    t.index ["visit_id"], name: "index_visit_photos_on_visit_id"
  end

  create_table "visits", force: :cascade do |t|
    t.decimal "checkin_lat", precision: 10, scale: 6
    t.decimal "checkin_lng", precision: 10, scale: 6
    t.decimal "checkout_lat", precision: 10, scale: 6
    t.decimal "checkout_lng", precision: 10, scale: 6
    t.string "client_uuid", null: false
    t.datetime "created_at", null: false
    t.datetime "ended_at"
    t.string "geofence_reason"
    t.integer "gps_mismatch_distance_m"
    t.string "no_order_reason"
    t.boolean "off_route", default: false, null: false
    t.bigint "route_id"
    t.bigint "seller_id", null: false
    t.datetime "started_at"
    t.integer "status", default: 0, null: false
    t.bigint "store_id", null: false
    t.datetime "updated_at", null: false
    t.date "visit_date"
    t.index ["client_uuid"], name: "index_visits_on_client_uuid", unique: true
    t.index ["route_id"], name: "index_visits_on_route_id"
    t.index ["seller_id", "visit_date"], name: "index_visits_on_seller_id_and_visit_date"
    t.index ["seller_id"], name: "index_visits_on_seller_id"
    t.index ["store_id", "started_at"], name: "index_visits_on_store_id_and_started_at"
    t.index ["store_id"], name: "index_visits_on_store_id"
  end

  create_table "warehouses", force: :cascade do |t|
    t.string "address"
    t.bigint "branch_id"
    t.datetime "created_at", null: false
    t.integer "status", default: 0, null: false
    t.datetime "updated_at", null: false
    t.string "wh_name", null: false
    t.string "whs_code", null: false
    t.index ["branch_id"], name: "index_warehouses_on_branch_id"
    t.index ["whs_code"], name: "index_warehouses_on_whs_code", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "assortment_items", "assortments"
  add_foreign_key "assortment_items", "products"
  add_foreign_key "assortments", "assortment_types"
  add_foreign_key "assortments", "branches"
  add_foreign_key "assortments", "channels"
  add_foreign_key "assortments", "store_categories", column: "store_category_ref_id"
  add_foreign_key "competitor_price_checks", "products"
  add_foreign_key "competitor_price_checks", "visits"
  add_foreign_key "device_tokens", "sellers"
  add_foreign_key "incentive_schemes", "branches"
  add_foreign_key "job_logs", "users", column: "triggered_by_id"
  add_foreign_key "order_batches", "branches"
  add_foreign_key "order_batches", "sellers"
  add_foreign_key "order_batches", "users", column: "downloaded_by_id"
  add_foreign_key "order_batches", "users", column: "locked_by_id"
  add_foreign_key "order_lines", "orders"
  add_foreign_key "order_lines", "products"
  add_foreign_key "order_lines", "promos"
  add_foreign_key "orders", "branches"
  add_foreign_key "orders", "order_batches"
  add_foreign_key "orders", "pricing_versions"
  add_foreign_key "orders", "routes"
  add_foreign_key "orders", "sellers"
  add_foreign_key "orders", "stores"
  add_foreign_key "orders", "visits"
  add_foreign_key "planograms", "channels"
  add_foreign_key "planograms", "users", column: "uploaded_by_id"
  add_foreign_key "pricing_rules", "pricing_versions"
  add_foreign_key "pricing_rules", "product_tiers"
  add_foreign_key "pricing_rules", "store_categories"
  add_foreign_key "pricing_versions", "users", column: "published_by_id"
  add_foreign_key "product_channels", "channels"
  add_foreign_key "product_channels", "products"
  add_foreign_key "products", "brands"
  add_foreign_key "products", "product_categories"
  add_foreign_key "products", "product_tiers"
  add_foreign_key "promo_eligibilities", "branches"
  add_foreign_key "promo_eligibilities", "channels"
  add_foreign_key "promo_eligibilities", "promos"
  add_foreign_key "promo_eligibilities", "store_categories", column: "store_category_ref_id"
  add_foreign_key "promo_lines", "products"
  add_foreign_key "promo_lines", "promos"
  add_foreign_key "promos", "users", column: "created_by_id"
  add_foreign_key "role_permissions", "permissions"
  add_foreign_key "role_permissions", "roles"
  add_foreign_key "routes", "branches"
  add_foreign_key "routes", "sellers"
  add_foreign_key "seller_daily_stats", "sellers"
  add_foreign_key "seller_targets", "branches"
  add_foreign_key "seller_targets", "sellers"
  add_foreign_key "sellers", "branches"
  add_foreign_key "sellers", "users"
  add_foreign_key "sellout_snapshots", "branches"
  add_foreign_key "sellout_snapshots", "products"
  add_foreign_key "sellout_snapshots", "sellers"
  add_foreign_key "sellout_snapshots", "stores"
  add_foreign_key "sku_sellout_snapshots", "products"
  add_foreign_key "sku_sellout_snapshots", "sellers"
  add_foreign_key "stock_counts", "products"
  add_foreign_key "stock_counts", "visits"
  add_foreign_key "stock_snapshots", "products"
  add_foreign_key "stock_snapshots", "stores"
  add_foreign_key "store_registrations", "branches"
  add_foreign_key "store_registrations", "channels"
  add_foreign_key "store_registrations", "sellers"
  add_foreign_key "store_registrations", "stores", column: "created_store_id"
  add_foreign_key "store_registrations", "stores", column: "duplicate_of_store_id"
  add_foreign_key "store_registrations", "stores", column: "provisional_store_id"
  add_foreign_key "store_registrations", "users", column: "reviewed_by_id"
  add_foreign_key "store_sku_sellouts", "stores"
  add_foreign_key "store_targets", "branches"
  add_foreign_key "store_targets", "stores"
  add_foreign_key "stores", "branches"
  add_foreign_key "stores", "channels"
  add_foreign_key "stores", "routes"
  add_foreign_key "stores", "sellers"
  add_foreign_key "stores", "store_categories"
  add_foreign_key "user_roles", "roles"
  add_foreign_key "user_roles", "users"
  add_foreign_key "users", "branches"
  add_foreign_key "visit_photos", "planograms"
  add_foreign_key "visit_photos", "visits"
  add_foreign_key "visits", "routes"
  add_foreign_key "visits", "sellers"
  add_foreign_key "visits", "stores"
  add_foreign_key "warehouses", "branches"
end
