module Api
  module V1
    # Field-manager app views: a combined team scoreboard and a per-seller drill
    # into store performance. Manager sees only the sellers assigned to them.
    class ManagerController < BaseController
      before_action :require_manager!

      # GET /api/v1/manager/team
      def team
        month = Date.current.beginning_of_month
        sellers = current_manager.sellers.active.where(primary_seller_id: nil).includes(:branch).order(:name)
        rows = sellers.map { |s| seller_kpi(s, month) }
        totals = {
          sellers: rows.size,
          target_amount: rows.sum { |r| r[:target_amount] },
          confirmed_actual: rows.sum { |r| r[:confirmed_actual] },
          presell_pending: rows.sum { |r| r[:presell_pending] },
          active_stores: rows.sum { |r| r[:active_stores] },
        }
        blended = totals[:confirmed_actual] + totals[:presell_pending]
        totals[:blended_actual] = blended
        totals[:attainment_pct] = totals[:target_amount].to_d.positive? ? (blended / totals[:target_amount] * 100).round : nil
        render json: { data: { manager: { name: current_manager.name }, period: month, totals: totals, sellers: rows }, meta: meta }
      end

      # GET /api/v1/manager/sellers/:id  → that seller's KPIs, per-assortment-type
      # rollup, and store-by-store performance.
      def seller
        s = current_manager.sellers.find(params[:id])
        month = Date.current.beginning_of_month
        ids = s.login_group_ids
        render json: { data: {
          seller: seller_kpi(s, month),
          assortment: seller_assortment_by_type(ids),
          stores: store_perf(ids, month),
        }, meta: meta }
      end

      # GET /api/v1/manager/stores/:id  → one store: target/attainment + per-type
      # assortment. Authorised to the manager's team stores only.
      def store
        store = Store.find(params[:id])
        return render_unauthorized unless team_store_ids.include?(store.id)

        month = Date.current.beginning_of_month
        render json: { data: {
          store: {
            store_id: store.id, name: store.name, code: store.code, branch: store.branch&.name,
            channel: store.channel&.name, category: store.category_letter,
            target_amount: store.target_for(month), confirmed_actual: store.confirmed_actual(month),
            presell_pending: store.pending_presell(month), blended_actual: store.blended_actual(month),
            attainment_pct: store.attainment_pct(month), active: store.active_in_vcsi?(month),
            last_stock_checked_on: store.last_stock_checked_at&.to_date,
          },
          assortment: store.assortment_by_type,
        }, meta: meta }
      end

      # GET /api/v1/manager/insights          → team-wide deep analytics (live)
      def insights
        reps = team_rep_codes(current_manager.team_seller_ids)
        render json: { data: cached_insights("team-#{current_manager.id}", reps: reps), meta: meta }
      end

      # GET /api/v1/manager/sellers/:id/insights
      def seller_insights
        s = current_manager.sellers.find(params[:id])
        reps = team_rep_codes(s.login_group_ids)
        render json: { data: cached_insights("seller-#{s.id}", reps: reps), meta: meta }
      end

      # GET /api/v1/manager/stores/:id/insights
      def store_insights
        store = Store.find(params[:id])
        return render_unauthorized unless team_store_ids.include?(store.id)

        reps = team_rep_codes([store.assigned_seller&.id].compact)
        render json: { data: cached_insights("store-#{store.id}", reps: reps, customer_id: store.vcsi_customer_ref), meta: meta }
      end

      private

      def team_rep_codes(seller_ids)
        Seller.where(id: seller_ids).where.not(vcsi_sales_rep_ref: [nil, ""]).distinct.pluck(:vcsi_sales_rep_ref)
      end

      # The month to report on — ?month=YYYY-MM (default current). Lets managers
      # look back at prior months.
      def report_month
        m = params[:month].to_s
        return Date.parse("#{m}-01") if m.match?(/\A\d{4}-\d{2}\z/)

        Date.current.beginning_of_month
      rescue ArgumentError
        Date.current.beginning_of_month
      end

      # Live vcsi pass-through is cached briefly so repeated taps don't hammer the
      # ERP; keyed to the reported month.
      def cached_insights(key, reps:, customer_id: nil)
        month = report_month
        ttl = SystemSetting.get("manager_insights_cache_seconds", 300).to_i
        Rails.cache.fetch("mgr_insights/#{key}/#{month.strftime('%Y%m')}", expires_in: ttl.seconds) do
          ManagerInsights.new(rep_codes: reps, customer_id: customer_id, month: month).call
        end
      end

      def group_stores(ids)
        Store.where(seller_id: ids)
             .or(Store.where(route_id: Route.where(seller_id: ids).select(:id)))
             .where.not(vcsi_customer_ref: [nil, ''])
      end

      def team_store_ids
        @team_store_ids ||= group_stores(current_manager.team_seller_ids).pluck(:id).to_set
      end

      # Pool each store's per-type compliance across the seller's (group's) stores.
      def seller_assortment_by_type(ids)
        agg = {}
        group_stores(ids).includes(:store_category).limit(300).find_each do |s|
          s.assortment_by_type.each do |row|
            a = (agg[row[:type_code]] ||= { type_name: row[:type_name], must: 0, carried: 0 })
            a[:must] += row[:must]
            a[:carried] += row[:carried]
          end
        end
        agg.map do |code, a|
          { type_code: code, type_name: a[:type_name], must: a[:must], carried: a[:carried],
            pct: (a[:must].positive? ? (a[:carried] * 100.0 / a[:must]).round : 0) }
        end
      end

      def seller_kpi(s, month)
        ids = s.login_group_ids
        confirmed = SelloutSnapshot.where(seller_id: ids, period_type: :mtd, period_date: month).sum(:amount)
        presell = Order.where(seller_id: ids).where.not(status: :cancelled)
                       .where(ordered_at: month.beginning_of_day..month.end_of_month.end_of_day).sum(:total_amount)
        target = SellerTarget.where(seller_id: ids, period_type: :mtd, period_date: month).sum(:target_amount).to_d
        blended = confirmed + presell
        {
          seller_id: s.id, name: s.name, branch: s.branch&.name,
          target_amount: target, confirmed_actual: confirmed, presell_pending: presell, blended_actual: blended,
          attainment_pct: (target.positive? ? (blended / target * 100).round : nil),
          pc_pct: s.route_productive_call_pct(month),
          active_stores: active_store_count(ids, month),
        }
      end

      def group_store_ids(ids)
        Store.where(seller_id: ids)
             .or(Store.where(route_id: Route.where(seller_id: ids).select(:id)))
             .pluck(:id)
      end

      def active_store_count(ids, month)
        store_ids = group_store_ids(ids)
        vcsi = Store.active_in_vcsi(month).where(id: store_ids).pluck(:id).to_set
        presell = Order.where(seller_id: ids, ordered_at: month..).where.not(status: :cancelled).distinct.pluck(:store_id).to_set
        (vcsi | presell).size
      end

      def store_perf(ids, month)
        store_ids = group_store_ids(ids)
        return [] if store_ids.empty?

        targets   = StoreTarget.for_month(month).where(store_id: store_ids).index_by(&:store_id)
        confirmed = SelloutSnapshot.where(store_id: store_ids, seller_id: nil, product_id: nil,
                                          period_type: :mtd, period_date: month).group(:store_id).sum(:amount)
        presell   = Order.where(store_id: store_ids).where.not(status: :cancelled)
                         .where(ordered_at: month.beginning_of_day..month.end_of_month.end_of_day)
                         .group(:store_id).sum(:total_amount)
        Store.where(id: store_ids).includes(:branch).order(:name).map do |st|
          conf = confirmed[st.id] || 0.to_d
          pre  = presell[st.id] || 0.to_d
          tgt  = targets[st.id]&.target_amount
          { store_id: st.id, name: st.name, code: st.code, branch: st.branch&.name,
            target_amount: tgt, confirmed_actual: conf, presell_pending: pre, blended_actual: conf + pre,
            attainment_pct: (tgt.to_d.positive? ? ((conf + pre) / tgt * 100).round : nil),
            active: conf.positive?, last_stock_checked_on: st.last_stock_checked_at&.to_date }
        end
      end
    end
  end
end
