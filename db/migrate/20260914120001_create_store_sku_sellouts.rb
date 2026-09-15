class CreateStoreSkuSellouts < ActiveRecord::Migration[8.1]
  def change
    create_table :store_sku_sellouts do |t|
      t.references :store, null: false, foreign_key: true
      t.string :it_barcode, null: false
      t.date :period_date, null: false            # month the confirmed sellout falls in
      t.decimal :pieces, precision: 12, scale: 2, default: 0
      t.decimal :amount, precision: 12, scale: 2, default: 0
      t.datetime :synced_at
      t.jsonb :raw, default: {}
      t.timestamps
    end
    # One confirmed row per store × barcode × month; carried = presence in the
    # trailing window. Upserted by the vcsi sku-sellout sync.
    add_index :store_sku_sellouts, [:store_id, :it_barcode, :period_date], unique: true,
              name: "index_store_sku_sellouts_unique"
    add_index :store_sku_sellouts, [:store_id, :period_date]
  end
end
