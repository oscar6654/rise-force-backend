module Vcsi
  # Pulls actual MTD sellout (GIV*1.12) per customer/store from vcsi_rise and
  # bulk-upserts a store-grain SelloutSnapshot (matched on vcsi_customer_ref ==
  # customer_id). This is the invoiced truth the store's presell "actual"
  # reconciles down to on each run.
  #
  # SCALE: writes go through upsert_all in batches (one INSERT ... ON CONFLICT
  # per batch) rather than a find+save per store, so a 20k-store sync is a
  # few dozen statements, not ~40k. Stores are looked up from a single
  # in-memory index built with one query.
  class StoreSelloutSyncJob < ApplicationJob
    queue_as :default
    BATCH_SIZE = 1_000

    def perform(month: Date.current.beginning_of_month, user: nil)
      JobLog.track(:store_sellout_sync, user: user) do |log|
        rows = VcsiRise::Client.new.store_sellout(month: month)
        log.total_rows = rows.size

        # customer_id => [store_id, branch_id] — one query, no per-row lookups.
        store_index = Store.where.not(vcsi_customer_ref: [nil, ""])
                           .pluck(:vcsi_customer_ref, :id, :branch_id)
                           .to_h { |ref, id, branch_id| [ref.to_s, [id, branch_id]] }

        now = Time.current
        mtd = SelloutSnapshot.period_types[:mtd]

        rows.each_slice(BATCH_SIZE) do |slice|
          records = slice.filter_map do |row|
            store_id, branch_id = store_index[row["customer_id"].to_s]
            next (log.skipped_rows += 1; nil) unless store_id

            log.processed_rows += 1
            {
              store_id: store_id, seller_id: nil, product_id: nil, branch_id: branch_id,
              period_type: mtd, period_date: month,
              amount: row["sellout"].to_d, quantity: row["transactions"].to_i,
              synced_at: now, raw: row, created_at: now, updated_at: now
            }
          end

          next if records.empty?

          SelloutSnapshot.upsert_all(records, unique_by: :index_sellout_snapshots_store_grain)
        end

        log.save!
      end
    end
  end
end
