module Vcsi
  # Derives each store's monthly target from its own vcsi_rise sales history.
  # vcsi_rise carries store HISTORY but no store TARGET, so SFA computes it:
  #
  #   target = (trailing N-month average actual sellout) * (1 + growth_rate)
  #
  # N (store_target_months) and growth_rate (store_target_growth_rate) are
  # SystemSettings. Runs entirely in SFA; vcsi_rise stays the read-only source.
  # Stores matched on vcsi_customer_ref == customer_id.
  #
  # SCALE: history is aggregated in memory (one pass), stores are read in one
  # query, and targets are written via upsert_all in batches — so a 20k-store
  # recompute is a handful of statements, not ~40k.
  class StoreTargetComputeJob < ApplicationJob
    queue_as :default
    BATCH_SIZE = 1_000

    def perform(month: Date.current.beginning_of_month, user: nil)
      months = SystemSetting.get("store_target_months", 3).to_i.clamp(1, 24)
      growth = SystemSetting.get("store_target_growth_rate", 0.05).to_d

      JobLog.track(:store_target_compute, user: user) do |log|
        # Trailing history through the last completed month (server default).
        history_rows = VcsiRise::Client.new.store_history(months: months)
        log.total_rows = history_rows.size

        # customer_id => summed sellout across the window (missing months = 0).
        totals = Hash.new(0.to_d)
        history_rows.each { |r| totals[r["customer_id"].to_s] += r["sellout"].to_d }

        now = Time.current
        monthly = StoreTarget.period_types[:monthly]

        Store.where.not(vcsi_customer_ref: [nil, ""])
             .pluck(:vcsi_customer_ref, :id, :branch_id)
             .each_slice(BATCH_SIZE) do |slice|
          records = slice.filter_map do |ref, store_id, branch_id|
            total = totals[ref.to_s]
            next (log.skipped_rows += 1; nil) if total.zero? # no vcsi history -> no derived target

            avg = total / months # average over the FULL window
            log.processed_rows += 1
            {
              store_id: store_id, branch_id: branch_id,
              period_type: monthly, period_date: month,
              target_amount: (avg * (1 + growth)).round(2),
              basis_amount: avg.round(2), months_used: months, growth_rate: growth,
              synced_at: now, created_at: now, updated_at: now
            }
          end

          next if records.empty?

          StoreTarget.upsert_all(records, unique_by: :index_store_targets_natural_key)
        end

        log.save!
      end
    end
  end
end
