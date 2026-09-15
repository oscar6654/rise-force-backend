class AddSellerGrainUniqueIndexToSelloutSnapshots < ActiveRecord::Migration[8.1]
  def change
    # Seller-grain snapshots (store_id/product_id NULL) need their own partial
    # unique index so upsert_all can ON CONFLICT on it — the natural_key index
    # includes the NULL store/product columns, which Postgres treats as distinct
    # and therefore won't dedupe. Mirrors the existing store_grain partial index.
    add_index :sellout_snapshots, [:seller_id, :period_type, :period_date],
              unique: true, where: "((store_id IS NULL) AND (product_id IS NULL))",
              name: "index_sellout_snapshots_seller_grain"
  end
end
