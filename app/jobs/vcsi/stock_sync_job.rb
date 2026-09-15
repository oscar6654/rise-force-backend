module Vcsi
  # Pulls actual on-hand stock from vcsi_rise. Row shape:
  #   { customer_ref, product_ref, quantity }
  class StockSyncJob < ApplicationJob
    queue_as :default

    def perform(as_of: Date.current, user: nil)
      JobLog.track(:stock_sync, user: user) do |log|
        rows = VcsiRise::Client.new.stock(as_of: as_of)
        log.total_rows = rows.size
        # Store × product scale (20k+ stores), so index lookups + upsert_all in
        # slices — never a per-row save.
        stores  = Store.where.not(vcsi_customer_ref: nil).index_by(&:vcsi_customer_ref)
        products = Product.where.not(vcsi_product_ref: nil).index_by(&:vcsi_product_ref)
        now = Time.current

        rows.each_slice(1_000) do |slice|
          records = slice.filter_map do |row|
            store = stores[row["customer_ref"].to_s]
            product = products[row["product_ref"].to_s]
            next (log.skipped_rows += 1; nil) unless store && product

            log.processed_rows += 1
            { store_id: store.id, product_id: product.id, as_of_date: as_of,
              quantity: row["quantity"].to_d, synced_at: now, raw: row, created_at: now, updated_at: now }
          end
          next if records.empty?

          StockSnapshot.upsert_all(records, unique_by: :idx_on_store_id_product_id_as_of_date_6194f60507)
        end
        log.save!
      end
    end
  end
end
