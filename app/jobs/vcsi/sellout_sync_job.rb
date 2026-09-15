module Vcsi
  # Pulls actual MTD sellout (GIV*1.12) per sales_rep from vcsi_rise and upserts
  # a seller-level SelloutSnapshot (matched on vcsi_sales_rep_ref == sales_rep).
  class SelloutSyncJob < ApplicationJob
    queue_as :default

    def perform(month: Date.current.beginning_of_month, user: nil)
      JobLog.track(:sellout_sync, user: user) do |log|
        rows = VcsiRise::Client.new.sellout(month: month)
        log.total_rows = rows.size
        sellers = Seller.where.not(vcsi_sales_rep_ref: nil).index_by(&:vcsi_sales_rep_ref)
        now = Time.current
        mtd = SelloutSnapshot.period_types[:mtd]
        synced_ids = []

        records = rows.filter_map do |row|
          seller = sellers[row["sales_rep"].to_s]
          next (log.skipped_rows += 1; nil) unless seller

          synced_ids << seller.id
          log.processed_rows += 1
          { seller_id: seller.id, store_id: nil, product_id: nil, branch_id: seller.branch_id,
            period_type: mtd, period_date: month,
            amount: row["sellout"].to_d, quantity: row["transactions"].to_i,
            synced_at: now, raw: row, created_at: now, updated_at: now }
        end

        records.each_slice(1_000) { |s| SelloutSnapshot.upsert_all(s, unique_by: :index_sellout_snapshots_seller_grain) }
        Seller.where(id: synced_ids).update_all(last_sync_at: now) if synced_ids.any?
        log.save!
      end
    end
  end
end
