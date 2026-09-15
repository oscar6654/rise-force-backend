module VcsiRise
  # On-demand, SELLER-SCOPED pull from vcsi_rise, triggered when a seller syncs
  # from the app. Pulls only that seller's data (filtered by sales_rep), so one
  # seller syncing doesn't fetch everyone's — and upserts:
  #   - the seller's own MTD sellout (seller-grain snapshot)
  #   - per-store MTD sellout for the stores that rep sold to (store-grain)
  #   - per-store per-barcode confirmed distribution for those stores (must-carry)
  #   - the seller's monthly target (from the seller master)
  #
  # Store TARGETS are NOT recomputed here — they're derived from trailing
  # history (stable within a month) by the daily Vcsi::StoreTargetComputeJob.
  # This service refreshes intraday ACTUALS only.
  class SellerSyncService
    Result = Struct.new(:ok, :reason, :seller_sellout, :store_rows, keyword_init: true)

    def initialize(seller, client: nil)
      @seller = seller
      @client = client || VcsiRise::Client.new
    end

    def call(month: Date.current.beginning_of_month)
      rep = @seller.vcsi_sales_rep_ref
      return Result.new(ok: false, reason: "seller has no vcsi_sales_rep_ref") if rep.blank?

      seller_amt = sync_seller_sellout(rep, month)
      store_rows = sync_store_sellout(rep, month)
      sync_store_distribution(rep, month)
      sync_target(rep, month)
      sync_focus_skus(rep, month)
      @seller.update_columns(last_sync_at: Time.current, vcsi_pulled_at: Time.current)

      Result.new(ok: true, seller_sellout: seller_amt, store_rows: store_rows)
    rescue StandardError => e
      Result.new(ok: false, reason: e.message)
    end

    private

    def sync_seller_sellout(rep, month)
      row = @client.sellout(month: month, sales_rep: rep).find { |r| r["sales_rep"].to_s == rep.to_s }
      return 0.to_d unless row

      snap = SelloutSnapshot.find_or_initialize_by(
        seller: @seller, store_id: nil, product_id: nil,
        period_type: SelloutSnapshot.period_types[:mtd], period_date: month
      )
      snap.assign_attributes(branch_id: @seller.branch_id, amount: row["sellout"].to_d,
                             quantity: row["transactions"].to_i, synced_at: Time.current, raw: row)
      snap.save!
      row["sellout"].to_d
    end

    def sync_store_sellout(rep, month)
      rows = @client.store_sellout(month: month, sales_rep: rep)
      customer_ids = rows.map { |r| r["customer_id"].to_s }
      stores = Store.where(vcsi_customer_ref: customer_ids).index_by(&:vcsi_customer_ref)
      now = Time.current

      records = rows.filter_map do |row|
        store = stores[row["customer_id"].to_s]
        next unless store

        {
          store_id: store.id, seller_id: nil, product_id: nil, branch_id: store.branch_id,
          period_type: SelloutSnapshot.period_types[:mtd], period_date: month,
          amount: row["sellout"].to_d, quantity: row["transactions"].to_i,
          synced_at: now, raw: row, created_at: now, updated_at: now
        }
      end

      SelloutSnapshot.upsert_all(records, unique_by: :index_sellout_snapshots_store_grain) if records.any?
      records.size
    end

    # Per-store, per-barcode confirmed sellout (net of CN) for the stores THIS
    # rep sold to — the "carried" truth for must-carry. Scoped to the seller so a
    # visit refreshes only their stores' distribution, not all 20k at once.
    def sync_store_distribution(rep, month)
      rows = @client.store_sku_sellout(month: month, sales_rep: rep)
      stores = Store.where(vcsi_customer_ref: rows.map { |r| r["customer_id"].to_s }).index_by(&:vcsi_customer_ref)
      now = Time.current

      records = rows.filter_map do |row|
        store = stores[row["customer_id"].to_s]
        barcode = row["it_barcode"].to_s.strip
        next if store.nil? || barcode.blank?

        { store_id: store.id, it_barcode: barcode, period_date: month,
          pieces: row["pieces"].to_d, amount: row["amount"].to_d,
          synced_at: now, raw: row, created_at: now, updated_at: now }
      end

      records.each_slice(1_000) { |s| StoreSkuSellout.upsert_all(s, unique_by: :index_store_sku_sellouts_unique) }
      records.size
    end

    # Pull confirmed PIECES for the focus SKUs used by any active focus_sku
    # scheme, so per-piece incentives run on true vcsi_rise data.
    def sync_focus_skus(rep, month)
      schemes = IncentiveScheme.live_on(month).for_seller(@seller).where(scheme_type: :focus_sku).to_a
      # Focus SKUs are keyed by it_barcode; support a legacy product_ids config too.
      barcodes = schemes.flat_map do |s|
        codes = Array(s.cfg[:it_barcodes]).map { |b| b.to_s.strip }
        if s.cfg[:product_ids].present?
          codes += Product.where(id: Array(s.cfg[:product_ids]).map(&:to_i))
                          .where.not(it_barcode: [nil, ""]).pluck(:it_barcode)
        end
        codes
      end.reject(&:blank?).uniq
      return if barcodes.empty?

      products = Product.where(it_barcode: barcodes).where.not(it_barcode: [nil, ""])
      by_barcode = products.index_by(&:it_barcode)
      return if by_barcode.empty?

      rows = @client.sku_sellout(month: month, sales_rep: rep, barcodes: barcodes)
      now = Time.current
      rows.each do |row|
        product = by_barcode[row["it_barcode"].to_s]
        next unless product

        snap = SkuSelloutSnapshot.find_or_initialize_by(seller: @seller, product: product, period_date: month)
        snap.assign_attributes(it_barcode: product.it_barcode, pieces: row["pieces"].to_d,
                               amount: row["amount"].to_d, synced_at: now)
        snap.save!
      end
    end

    def sync_target(rep, month)
      row = @client.sellers(sales_rep: rep).find { |r| r["sales_rep"].to_s == rep.to_s }
      return unless row

      @seller.update_columns(
        sales_target: row["sales_target"],
        supervisor_name: row["supervisor_name"].presence || @seller.supervisor_name,
        gsm_name: row["gsm_name"].presence || @seller.gsm_name,
        om_name: row["om_name"].presence || @seller.om_name
      )
      target = SellerTarget.find_or_initialize_by(
        seller: @seller, period_type: SellerTarget.period_types[:mtd], period_date: month
      )
      target.assign_attributes(branch_id: @seller.branch_id,
                               target_amount: row["sales_target"].to_d, synced_at: Time.current)
      target.save!
    end
  end
end
