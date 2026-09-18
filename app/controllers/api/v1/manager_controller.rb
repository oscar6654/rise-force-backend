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

      # GET /api/v1/manager/sellers/:id  → that seller's store-by-store performance.
      def seller
        s = current_manager.sellers.find(params[:id])
        month = Date.current.beginning_of_month
        render json: { data: { seller: seller_kpi(s, month), stores: store_perf(s.login_group_ids, month) }, meta: meta }
      end

      private

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
