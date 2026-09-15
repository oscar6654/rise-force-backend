class AddStoreGrainIndexToSelloutSnapshots < ActiveRecord::Migration[8.1]
  # Store-grain sellout rows have seller_id/product_id NULL, so the existing
  # natural-key index can't serve as an ON CONFLICT target (NULLs are distinct
  # in a unique index). This partial index gives bulk upsert_all a clean,
  # unambiguous conflict target for the store grain.
  def change
    add_index :sellout_snapshots, [:store_id, :period_type, :period_date],
              unique: true,
              where: "seller_id IS NULL AND product_id IS NULL",
              name: "index_sellout_snapshots_store_grain"
  end
end
