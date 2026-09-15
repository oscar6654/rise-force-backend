module Vcsi
  # Pulls the seller master + monthly target from vcsi_rise and upserts a
  # SellerTarget per local Seller (matched on vcsi_sales_rep_ref == sales_rep).
  # Also enriches the local seller master (supervisor/target column) so the
  # SFA console shows targets tagged to the user / supervisor.
  class TargetSyncJob < ApplicationJob
    queue_as :default

    def perform(month: Date.current.beginning_of_month, user: nil)
      JobLog.track(:target_sync, user: user) do |log|
        rows = VcsiRise::Client.new.sellers
        log.total_rows = rows.size
        sellers = Seller.where.not(vcsi_sales_rep_ref: nil).index_by(&:vcsi_sales_rep_ref)
        now = Time.current
        mtd = SellerTarget.period_types[:mtd]

        records = rows.filter_map do |row|
          seller = sellers[row["sales_rep"].to_s]
          next (log.skipped_rows += 1; nil) unless seller

          # Per-seller denorm (bounded by seller count, ~hundreds) — distinct
          # values per seller, so one lightweight update each.
          seller.update_columns(
            sales_target: row["sales_target"],
            supervisor_name: row["supervisor_name"].presence || seller.supervisor_name,
            gsm_name: row["gsm_name"].presence || seller.gsm_name,
            om_name: row["om_name"].presence || seller.om_name
          )
          log.processed_rows += 1
          { seller_id: seller.id, branch_id: seller.branch_id, period_type: mtd, period_date: month,
            target_amount: row["sales_target"].to_d, synced_at: now, created_at: now, updated_at: now }
        end

        records.each_slice(1_000) { |s| SellerTarget.upsert_all(s, unique_by: :idx_on_seller_id_period_type_period_date_1b205bac0d) }
        log.save!
      end
    end
  end
end
