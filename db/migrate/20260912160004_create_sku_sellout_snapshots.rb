class CreateSkuSelloutSnapshots < ActiveRecord::Migration[8.1]
  # Per-seller per-SKU confirmed sellout (pieces) pulled from vcsi_rise, scoped
  # to focus SKUs so the feed stays small. Powers focus-SKU incentives on true data.
  def change
    create_table :sku_sellout_snapshots do |t|
      t.references :seller, null: false, foreign_key: true
      t.references :product, null: true, foreign_key: true
      t.string :it_barcode
      t.date :period_date, null: false
      t.decimal :pieces, precision: 14, scale: 2, default: 0, null: false
      t.decimal :amount, precision: 14, scale: 2, default: 0, null: false
      t.datetime :synced_at
      t.timestamps
    end
    add_index :sku_sellout_snapshots, [:seller_id, :product_id, :period_date], unique: true, name: "idx_sku_sellout_natural"
  end
end
