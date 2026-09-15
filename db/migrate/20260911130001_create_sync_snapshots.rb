class CreateSyncSnapshots < ActiveRecord::Migration[8.1]
  def change
    create_table :sellout_snapshots do |t|
      t.references :branch, foreign_key: true, null: true
      t.references :seller, foreign_key: true, null: true
      t.references :store, foreign_key: true, null: true
      t.references :product, foreign_key: true, null: true
      t.integer  :period_type, null: false, default: 1   # daily/mtd/monthly
      t.date     :period_date, null: false
      t.decimal  :amount, precision: 14, scale: 2, null: false, default: 0
      t.decimal  :quantity, precision: 14, scale: 2, null: false, default: 0
      t.datetime :synced_at
      t.jsonb    :raw, null: false, default: {}

      t.timestamps
    end
    add_index :sellout_snapshots, [:seller_id, :period_type, :period_date, :store_id, :product_id],
              unique: true, name: "index_sellout_snapshots_natural_key"

    create_table :stock_snapshots do |t|
      t.references :store, foreign_key: true, null: false
      t.references :product, foreign_key: true, null: false
      t.decimal  :quantity, precision: 14, scale: 2, null: false, default: 0
      t.date     :as_of_date, null: false
      t.datetime :synced_at
      t.jsonb    :raw, null: false, default: {}

      t.timestamps
    end
    add_index :stock_snapshots, [:store_id, :product_id, :as_of_date], unique: true

    create_table :seller_targets do |t|
      t.references :seller, foreign_key: true, null: false
      t.references :branch, foreign_key: true, null: true
      t.integer  :period_type, null: false, default: 2   # mtd/monthly
      t.date     :period_date, null: false               # month anchor
      t.decimal  :target_amount, precision: 14, scale: 2, null: false, default: 0
      t.decimal  :target_quantity, precision: 14, scale: 2
      t.datetime :synced_at

      t.timestamps
    end
    add_index :seller_targets, [:seller_id, :period_type, :period_date], unique: true
  end
end
