class CreateFieldCapture < ActiveRecord::Migration[8.1]
  def change
    create_table :visits do |t|
      t.string   :client_uuid, null: false
      t.references :seller, foreign_key: true, null: false
      t.references :store, foreign_key: true, null: false
      t.references :route, foreign_key: true, null: true
      t.integer  :status, null: false, default: 0   # planned/in_progress/closed_with_order/closed_no_order
      t.boolean  :off_route, null: false, default: false
      t.decimal  :checkin_lat, precision: 10, scale: 6
      t.decimal  :checkin_lng, precision: 10, scale: 6
      t.decimal  :checkout_lat, precision: 10, scale: 6
      t.decimal  :checkout_lng, precision: 10, scale: 6
      t.integer  :gps_mismatch_distance_m
      t.datetime :started_at
      t.datetime :ended_at
      t.string   :no_order_reason
      t.date     :visit_date

      t.timestamps
    end
    add_index :visits, :client_uuid, unique: true
    add_index :visits, [:seller_id, :visit_date]
    add_index :visits, [:store_id, :started_at]

    create_table :stock_counts do |t|
      t.string   :client_uuid, null: false
      t.references :visit, foreign_key: true, null: false
      t.references :product, foreign_key: true, null: false
      t.decimal  :qty, precision: 12, scale: 2, null: false, default: 0
      t.integer  :prefilled_from, null: false, default: 0  # none/last_order/last_visit

      t.timestamps
    end
    add_index :stock_counts, :client_uuid, unique: true
    add_index :stock_counts, [:visit_id, :product_id], unique: true

    create_table :competitor_price_checks do |t|
      t.string   :client_uuid, null: false
      t.references :visit, foreign_key: true, null: false
      t.references :product, foreign_key: true, null: true
      t.string   :product_label
      t.decimal  :our_price, precision: 12, scale: 2
      t.string   :competitor_name
      t.decimal  :competitor_price, precision: 12, scale: 2
      t.text     :notes

      t.timestamps
    end
    add_index :competitor_price_checks, :client_uuid, unique: true

    create_table :visit_photos do |t|
      t.string   :client_uuid, null: false
      t.references :visit, foreign_key: true, null: false
      t.references :planogram, foreign_key: true, null: true
      t.integer  :kind, null: false, default: 0   # planogram_compliance/storefront/other

      t.timestamps
    end
    add_index :visit_photos, :client_uuid, unique: true
  end
end
