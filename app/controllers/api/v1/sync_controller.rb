module Api
  module V1
    # Delta master-data sync for the seller app. All endpoints accept
    # ?updated_since=<iso8601> and return meta.server_time as the next cursor.
    class SyncController < BaseController
      include CdnAssetsHelper # cdn_url for photos/planograms

      def bootstrap
        render json: {
          data: {
            pricing_version: PricingVersion.current&.version_number,
            config: {
              geofence_mode: SystemSetting.get("checkin_geofence_mode", "soft"),
              geofence_radius_m: SystemSetting.get("checkin_geofence_radius_m", 150).to_i,
            },
            latest: {
              products:   Product.maximum(:updated_at),
              stores:     seller_stores.maximum(:updated_at),
              promos:     Promo.maximum(:updated_at),
              planograms: Planogram.maximum(:updated_at)
            }
          },
          meta: meta
        }
      end

      def products
        # Collapse to ONE item_key per barcode (highest-priced representative) so
        # the app's catalog isn't cluttered with 20 packs of the same product.
        # Barcode-less SKUs pass through individually.
        rep_ids = Product.barcode_representative_ids.values.to_set
        chan_by_barcode = Product.channel_ids_by_barcode
        scope = since_scope(Product.includes(:brand, :product_category, :product_tier, :product_channels).where(status: :active))
        rows = scope.select { |p| p.it_barcode.blank? || rep_ids.include?(p.id) }.map do |p|
          # channel_ids empty = universal (visible in every channel); non-empty =
          # only those channels. Union across the barcode group so collapsing
          # never hides the product from a channel a sibling maps to.
          channel_ids = p.it_barcode.present? ? (chan_by_barcode[p.it_barcode] || []) : p.product_channels.map(&:channel_id)
          { id: p.id, itemkey: p.sku, desc1: p.description, desc2: p.desc2,
            brand: p.brand&.name, category: p.product_category&.name, item_tier: p.tier,
            it_barcode: p.it_barcode, cs_barcode: p.cs_barcode,
            stock_uom: p.stock_uom, selling_uom: p.selling_uom, items_per_case: p.pcs_per_case,
            item_cost: p.item_cost, case_cost: p.case_cost,
            channel_ids: channel_ids,
            photo_url: (cdn_url(p.photo) if p.photo.attached?),
            updated_at: p.updated_at }
        end
        render json: { data: rows, meta: meta }
      end

      # Resolved store prices for the seller's store categories.
      def prices
        resolver = PricingResolver.new
        category_ids = seller_stores.distinct.pluck(:store_category_id).compact
        categories = StoreCategory.where(id: category_ids)
        products = Product.where(status: :active)
        rows = []
        categories.each do |cat|
          products.each do |p|
            pc_price = resolver.price_for(cat, p, uom: :pc)
            case_price = resolver.price_for(cat, p, uom: :case)
            next if pc_price.nil? && case_price.nil?

            rows << { product_id: p.id, store_category: cat.code, pc_price: pc_price, case_price: case_price }
          end
        end
        render json: { data: { pricing_version: resolver.version_number, prices: rows }, meta: meta }
      end

      def stores
        # Active = invoiced in vcsi_rise this month. Batch-load the id set once
        # (no per-store query) so the app can badge active stores.
        active_ids = Store.active_in_vcsi.where(id: seller_stores.select(:id)).pluck(:id).to_set
        rows = since_scope(seller_stores).map { |s| store_json(s).merge(active: active_ids.include?(s.id)) }
        render json: { data: rows, meta: meta }
      end

      def routes
        rows = since_scope(Route.where(seller: current_seller)).map do |r|
          { id: r.id, code: r.code, name: r.name, store_ids: r.stores.pluck(:id) }
        end
        render json: { data: rows, meta: meta }
      end

      def channels
        rows = since_scope(Channel.where(status: :active)).map { |c| { id: c.id, code: c.code, name: c.name } }
        render json: { data: rows, meta: meta }
      end

      def planograms
        rows = since_scope(Planogram.where(status: :active)).map do |pl|
          { id: pl.id, channel_id: pl.channel_id, title: pl.title,
            file_url: (cdn_url(pl.file) if pl.file.attached?), effective_date: pl.effective_date }
        end
        render json: { data: rows, meta: meta }
      end

      def promos
        store = current_seller.branch && Store.find_by(id: params[:store_id])
        scope = store ? Promo.eligible_for(store) : Promo.all
        rows = since_scope(scope.where(status: :active).includes(:promo_lines)).map do |pr|
          { id: pr.id, code: pr.code, name: pr.name, mechanic_type: pr.mechanic_type,
            start_date: pr.start_date, end_date: pr.end_date, config: pr.config,
            per_store_limit: pr.per_store_limit, # nil/0 = unlimited; app pre-checks avails
            store_avails: store ? pr.avails_for(store) : nil, # times THIS store already availed
            lines: pr.promo_lines.map { |l| { role: l.role, it_barcode: l.it_barcode,
              product_ids: (l.it_barcode.present? ? Product.where(it_barcode: l.it_barcode).pluck(:id) : [l.product_id].compact),
              min_qty: l.min_qty, reward_qty: l.reward_qty, discount_rate: l.discount_rate,
              discount_amount: l.discount_amount, fixed_price: l.fixed_price } } }
        end
        render json: { data: rows, meta: meta }
      end

      # POST /api/v1/sync/refresh
      # On-demand, SELLER-SCOPED pull from vcsi_rise for the current seller.
      # Throttled (seller_pull_throttle_seconds, default 300s) so repeated
      # pull-to-refresh doesn't hammer vcsi_rise. After this, the app reads the
      # fresh numbers from /sync/store_performance and /me/targets.
      def refresh
        throttle = SystemSetting.get("seller_pull_throttle_seconds", 300).to_i
        last = current_seller.vcsi_pulled_at

        if last && last > throttle.seconds.ago
          return render json: { data: { refreshed: false, throttled: true, last_pulled_at: last.iso8601,
                                        retry_after_seconds: (throttle - (Time.current - last)).to_i },
                                meta: meta }
        end

        result = VcsiRise::SellerSyncService.new(current_seller).call
        current_seller.reload
        render json: {
          data: { refreshed: result.ok, throttled: false, reason: result.reason,
                  stores_updated: result.store_rows,
                  last_pulled_at: current_seller.vcsi_pulled_at&.iso8601,
                  summary: current_seller.headline }, # headline target vs actual, one round-trip
          meta: meta
        }, status: (result.ok ? :ok : :unprocessable_entity)
      end

      # GET /api/v1/sync/store_performance?updated_since=<iso8601>
      # Per-store achievement for THIS seller's stores, derived from vcsi_rise
      # (target + confirmed actual + active flag). DELTA on the vcsi sync time:
      # with updated_since, only returns stores whose vcsi_rise data changed
      # since then ("when there is new in rise"). Batched — no per-store queries.
      def store_performance
        month = Date.current.beginning_of_month
        store_ids = seller_stores.pluck(:id)
        return render(json: { data: [], meta: meta }) if store_ids.empty?

        targets   = StoreTarget.for_month(month).where(store_id: store_ids)
                               .to_h { |t| [t.store_id, t] }
        grain     = SelloutSnapshot.where(store_id: store_ids, seller_id: nil, product_id: nil,
                                          period_type: :mtd, period_date: month)
        confirmed = grain.group(:store_id).sum(:amount)
        last_sync = grain.group(:store_id).maximum(:synced_at)

        # "To invoice" per store = value of SFA presell orders taken this month,
        # pending OSB invoicing. A distinct pipeline from vcsi_rise confirmed
        # sellout (mostly non-SFA DMS sales, can be negative from credit notes), so
        # NOT reconciled against confirmed — just what the store ordered.
        presell = Hash.new(0.to_d)
        Order.where(store_id: store_ids).where.not(status: :cancelled)
             .where(ordered_at: month.beginning_of_day..month.end_of_month.end_of_day)
             .group(:store_id).sum(:total_amount).each { |sid, amt| presell[sid] = amt.to_d }

        since = updated_since
        rows = store_ids.filter_map do |sid|
          target = targets[sid]
          conf   = confirmed[sid] || 0.to_d
          # Store's freshness = newest vcsi write across its target and sellout.
          synced = [target&.synced_at, last_sync[sid]].compact.max

          if since
            next if synced.nil? || synced <= since # nothing new from rise
          else
            next if target.nil? && conf.zero?      # first sync: skip empty stores
          end

          blended = conf + presell[sid]
          tgt_amt = target&.target_amount
          {
            store_id: sid,
            target_amount: tgt_amt,
            confirmed_actual: conf,
            presell_pending: presell[sid],
            blended_actual: blended,
            attainment_pct: (tgt_amt.to_d.positive? ? (blended / tgt_amt * 100).round : nil),
            active: conf.positive?, # invoiced in vcsi_rise this month
            synced_at: synced&.iso8601
          }
        end

        render json: { data: rows, meta: meta }
      end

      # Resolved must-stock list for a store.
      def assortments
        store = Store.find(params.require(:store_id))
        items = Assortment.resolved_items_for(store).includes(:product)
        rows = items.map { |i| { product_id: i.product_id, sku: i.product.sku, must_stock: i.must_stock, priority: i.priority } }
        render json: { data: rows, meta: meta }
      end

      private

      def seller_stores
        # Union across the login group so one login sees BOTH branches' stores.
        # Plain Store.where clauses (route match via subquery) so `.or` stays
        # structurally compatible and routeless stores aren't dropped by a join.
        ids = current_group_ids
        branch_ids = Seller.where(id: ids).distinct.pluck(:branch_id)
        route_store_ids = Store.joins(:route).where(routes: { seller_id: ids }).select(:id)
        Store.where(seller_id: ids)
             .or(Store.where(id: route_store_ids))
             .or(Store.where(branch_id: branch_ids))
      end

      def store_json(s)
        { id: s.id, store_code: s.store_code, provisional_code: s.provisional_code,
          name: s.name, owner_name: s.owner_name, address: s.address,
          latitude: s.latitude, longitude: s.longitude, channel_id: s.channel_id,
          category: s.category, status: s.status, route_id: s.route_id,
          visit_frequency: s.visit_frequency, week_pattern: s.week_pattern,
          visit_day: s.visit_day, visit_sequence: s.visit_sequence, updated_at: s.updated_at }
      end
    end
  end
end
