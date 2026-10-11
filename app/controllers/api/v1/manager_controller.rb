module Api
  module V1
    # Field-manager app views: a combined team scoreboard and a per-seller drill
    # into store performance. Manager sees only the sellers assigned to them.
    class ManagerController < BaseController
      include DisplayApi
      include SellerPerformanceApi
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

      # GET /api/v1/manager/display → active display campaigns, per team store:
      # executed vs missing target lines. View-only (uploads are console-side).
      # Uses the display store scope (not team_store_ids) because a display-target
      # store need not be vcsi-linked.
      def display
        render json: { data: { campaigns: display_campaigns_payload(display_team_store_ids.to_a) }, meta: meta }
      end

      # GET /api/v1/manager/display/stores/:store_id → one store across all live
      # campaigns, with target lines + execution photos.
      def display_store
        store = Store.find(params[:store_id])
        return render_unauthorized unless display_team_store_ids.include?(store.id)

        render json: { data: display_store_detail(store), meta: meta }
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

      def team_store_ids
        @team_store_ids ||= group_stores(current_manager.team_seller_ids).pluck(:id).to_set
      end

      # Stores for display targets: all the team's stores (vcsi link not required).
      def display_team_store_ids
        @display_team_store_ids ||= display_store_ids_for(current_manager.team_seller_ids).to_set
      end

    end
  end
end
