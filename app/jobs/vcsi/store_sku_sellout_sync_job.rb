module Vcsi
  # Pulls per-STORE per-SKU confirmed (invoiced, net of credit notes) sellout
  # from vcsi_rise and bulk-upserts a StoreSkuSellout per store × barcode × month.
  # This is the "carried" truth for must-carry compliance: an order of 20 that
  # invoices to 10 (or is returned via CN) syncs down to 10 (see
  # Store#carried_dist_keys). Optional endpoint — if vcsi_rise hasn't deployed it,
  # the client returns [] and must-carry stays on SFA presell orders.
  #
  # SCALE: upsert_all in batches (one INSERT ... ON CONFLICT per batch); stores
  # resolved from a single in-memory customer_id index.
  class StoreSkuSelloutSyncJob < ApplicationJob
    queue_as :default
    BATCH_SIZE = 1_000

    def perform(month: Date.current.beginning_of_month, user: nil)
      JobLog.track(:store_sku_sellout_sync, user: user) do |log|
        rows = VcsiRise::Client.new.store_sku_sellout(month: month)
        log.total_rows = rows.size

        store_index = Store.where.not(vcsi_customer_ref: [nil, ""])
                           .pluck(:vcsi_customer_ref, :id)
                           .to_h { |ref, id| [ref.to_s, id] }
        now = Time.current

        rows.each_slice(BATCH_SIZE) do |slice|
          records = slice.filter_map do |row|
            store_id = store_index[row["customer_id"].to_s]
            barcode  = row["it_barcode"].to_s.strip
            next (log.skipped_rows += 1; nil) if store_id.nil? || barcode.blank?

            log.processed_rows += 1
            { store_id: store_id, it_barcode: barcode, period_date: month,
              pieces: row["pieces"].to_d, amount: row["amount"].to_d,
              synced_at: now, raw: row, created_at: now, updated_at: now }
          end
          next if records.empty?

          StoreSkuSellout.upsert_all(records, unique_by: :index_store_sku_sellouts_unique)
        end
      end
    end
  end
end
